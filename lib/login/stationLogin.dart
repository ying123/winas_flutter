import 'package:redux/redux.dart';
import 'package:flutter/material.dart';

import './stationList.dart';
import './loginDeviceFailed.dart';

import '../redux/redux.dart';
import '../common/utils.dart';
import '../common/request.dart';
import '../transfer/manager.dart';
import '../common/stationApis.dart';

/// Login to device
stationLogin(BuildContext context, Request request, Station currentDevice,
    Account account, Store<AppState> store,
    {bool shouldShowDialog = false}) async {
  assert(currentDevice != null);

  // cancel network monitor
  if (store?.state?.apis != null) {
    store.state.apis?.monitorCancel();
  }

  final deviceSN = currentDevice.sn;
  final lanIp = currentDevice.lanIp;
  final deviceName = currentDevice.name;
  final boot = await request.req(
    'localBoot',
    {'deviceSN': deviceSN},
  ).timeout(Duration(seconds: 10));

  final state = boot.data['state'];
  if (state != 'STARTED' && shouldShowDialog) {
    // ProbeFailed, EMBEDVOLUMEFAILED
    if (state == 'EMBEDVOLUMEFAILED') {
      final code = boot.data['error']['code'];
      // EVOLUMEFILE, EVOLUMENOTFOUND, EVOLUMEFORMAT, EVOLUMEMISS

      List<Block> blks = [];
      if (boot.data['storage'] != null) {
        blks = List.from(
          boot.data['storage']['blocks'].map((b) => Block.fromMap(b)),
        );
      }
      debug('EMBEDVOLUMEFAILED $code $blks');
      showDialog(
        context: context,
        builder: (BuildContext context) => LoginDeviceFailed(
          code: code,
          blks: blks,
          request: request,
          deviceSN: deviceSN,
        ),
      );
      throw 'EMBEDVOLUMEFAILED $code';
    }
  }

  List results = await Future.wait([
    request.req(
        'localUsers', {'deviceSN': deviceSN}).timeout(Duration(seconds: 10)),
    request.req('localToken', {'deviceSN': deviceSN}),
    request.req('localDrives', {'deviceSN': deviceSN}),
    request.testLAN(lanIp, deviceSN),
  ]);

  bool isCloud = !results[3];

  final lanToken = results[1].data['token'];

  assert(lanToken != null);

  // update StatinData
  store.dispatch(
    DeviceLoginAction(
      Device(
        deviceSN: deviceSN,
        deviceName: deviceName,
        lanIp: lanIp,
        lanToken: lanToken,
      ),
    ),
  );
  assert(results[0].data is List);

  // get current user data
  final user = results[0].data.firstWhere(
        (s) => s['winasUserId'] == account.id,
        orElse: () => null,
      );

  store.dispatch(
    UpdateUserAction(
      User.fromMap(user),
    ),
  );

  // get current drives data
  List<Drive> drives = List.from(
    results[2].data.map((drive) => Drive.fromMap(drive)),
  );

  store.dispatch(
    UpdateDrivesAction(drives),
  );

  // cloud apis
  store.dispatch(
    UpdateCloudAction(request),
  );

  // station apis
  String cookie = request.cookie;
  Apis apis = Apis(
      account.token, lanIp, lanToken, account.id, isCloud, deviceSN, cookie);

  // start to monitor network change
  apis.monitorStart();

  store.dispatch(
    UpdateApisAction(apis),
  );

  if (user['uuid'] != null) {
    // init TransferManager, load TransferItem
    TransferManager.init(user['uuid'], store.state).catchError(print);
  }

  // set lastUserDeviceSn
  request.req('setLastSN', {'sn': deviceSN}).catchError(print);

  // log login event via umeng
  loginLog(account.id, deviceSN).catchError(print);
}

/// Request station list
Future reqStationList(Request request) async {
  final stationsRes = await request.req('stations', null);
  final lastUseDeviceSn = stationsRes.data['lastUseDeviceSn'];
  List<Station> stationList = List.from(
    stationsRes.data['ownStations'].map(
      (s) => Station.fromMap(s, isOwner: true),
    ),
  );
  List<Station> sharedStations = List.from(
    stationsRes.data['sharedStations'].map(
      (s) => Station.fromMap(s, isOwner: false),
    ),
  );
  // add shared device
  stationList.addAll(sharedStations);

  final lastDevice = stationList.firstWhere(
      (s) => s.sn == lastUseDeviceSn && s.sn != null,
      orElse: () => null);

  return ({
    'stationList': stationList,
    'lastDevice': lastDevice,
  });
}

/// Request station list and try login to lastDevice
deviceLogin(
    BuildContext context, Request request, Account account, store) async {
  // request station list
  List<Station> stationList;
  Station lastDevice;
  try {
    final result = await reqStationList(request);
    stationList = result['stationList'];
    lastDevice = result['lastDevice'];
  } catch (error) {
    debug(error);
    stationList = null;
    lastDevice = null;
  }

  // find lastDevice and device is online, try login
  bool success = false;
  if (lastDevice != null && lastDevice.isOnline) {
    try {
      await stationLogin(context, request, lastDevice, account, store);
      success = true;
    } catch (error) {
      debug(error);
      success = false;
    }
  }

  if (success) {
    // remove all router, and push '/station'
    Navigator.pushNamedAndRemoveUntil(
        context, '/station', (Route<dynamic> route) => false);
    return;
  } else {
    // no availiable last device
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        settings: RouteSettings(name: 'stationList'),
        builder: (context) {
          return StationList(
            request: request,
            stationList: stationList,
          );
        },
      ),
      (Route<dynamic> route) => false,
    );
  }
}
