import 'package:redux/redux.dart';
import '../common/format.dart';
import '../common/stationApis.dart';

// structure of xxData
class Account {
  String token;
  String nickName;
  String username;
  String avatarUrl;
  String id;
  String mail;
  Account(
      {this.token,
      this.nickName,
      this.username,
      this.avatarUrl,
      this.id,
      this.mail});
  Account.fromMap(Map m) {
    this.token = m['token'];
    this.nickName = m['nickName'];
    this.username = m['username'];
    this.avatarUrl = m['avatarUrl'];
    this.id = m['id'];
    this.mail = m['mail'];
  }
}

class Device {
  String deviceSN;
  String deviceName;
  String lanIp;
  String lanToken;
  Device({this.deviceSN, this.deviceName, this.lanIp, this.lanToken});
}

class User {
  String uuid;
  String username;
  bool isFirstUser;
  String status;
  String phoneNumber;
  String winasUserId;
  String avatarUrl;

  User.fromMap(Map m) {
    this.uuid = m['uuid'];
    this.username = m['username'];
    this.isFirstUser = m['isFirstUser'];
    this.status = m['status'];
    this.phoneNumber = m['phoneNumber'];
    this.winasUserId = m['winasUserId'];
    this.avatarUrl = m['avatarUrl'];
  }
}

class DriveClient {
  String id;

  bool disabled;
  int lastBackupTime;

  /// Idle, Working, Failed
  String status;

  /// Win-PC, Linux-PC, Mac-PC, iOS, Android
  String type;

  DriveClient({this.type});

  DriveClient.fromMap(Map m) {
    this.id = m['id'];
    this.status = m['status'];
    this.disabled = m['disabled'];
    this.lastBackupTime = m['lastBackupTime'];
    this.type = m['type'];
  }
}

class Drive {
  String uuid;
  String type;
  bool privacy;
  String owner;
  String tag;
  String label;
  bool isDeleted;
  bool smb;
  int ctime;
  int mtime;
  int dirCount = 0;
  int fileCount = 0;
  String fileTotalSize = '';
  DriveClient client;
  Drive({this.uuid, this.tag, this.type, this.label, this.client});
  Drive.fromMap(Map m) {
    this.uuid = m['uuid'];
    this.type = m['type'];
    this.privacy = m['privacy'];
    this.owner = m['owner'];
    this.tag = m['tag'];
    this.label = m['label'];
    this.isDeleted = m['isDeleted'];
    this.smb = m['smb'];
    this.ctime = m['ctime'];
    this.mtime = m['mtime'];
    this.client = m['client'] == null ? null : DriveClient.fromMap(m['client']);
  }
  void updateStats(Map s) {
    this.dirCount = s['dirCount'];
    this.fileCount = s['fileCount'];
    this.fileTotalSize = prettySize(s['fileTotalSize']);
  }
}

class Metadata {
  String type;
  Metadata.fromMap(Map m) {
    this.type = m['type'];
  }
}

class Entry {
  int size;
  int ctime;
  int mtime;
  String name;
  String uuid;
  String type;
  String hash;
  String hsize;
  String hmtime;
  String pdir;
  String pdrv;
  List namepath;
  Metadata metadata;
  bool selected = false;
  Entry({this.name, this.uuid, this.type, this.pdir, this.pdrv});
  Entry.fromMap(Map m) {
    this.size = m['size'];
    this.ctime = m['ctime'];
    this.mtime = m['mtime'];
    this.name = m['bname'] ?? m['name'];
    this.uuid = m['uuid'];
    this.type = m['type'];
    this.hash = m['hash'];
    this.hsize = prettySize(this.size);
    this.hmtime = prettyDate(this.mtime);
    this.metadata =
        m['metadata'] == null ? null : Metadata.fromMap(m['metadata']);
  }

  Entry.fromSearch(Map m, List<String> d) {
    this.size = m['size'];
    this.ctime = m['ctime'];
    this.mtime = m['mtime'];
    this.name = m['name'];
    this.uuid = m['uuid'];
    this.type = 'file';
    this.hash = m['hash'];
    this.hsize = prettySize(this.size);
    this.hmtime = prettyDate(this.mtime);
    this.metadata =
        m['metadata'] == null ? null : Metadata.fromMap(m['metadata']);
    this.pdir = m['pdir'];
    this.pdrv = d[m['place']];
    this.namepath = m['namepath'];
  }

  Entry.mixNode(Map m, Node n) {
    this.size = m['size'];
    this.ctime = m['ctime'];
    this.mtime = m['mtime'];
    this.name = m['bname'] ?? m['name'];
    this.uuid = m['uuid'];
    this.type = m['type'];
    this.hash = m['hash'];
    this.hsize = prettySize(this.size);
    this.hmtime = prettyDate(this.mtime);
    this.metadata =
        m['metadata'] == null ? null : Metadata.fromMap(m['metadata']);
    this.pdir = n.dirUUID;
    this.pdrv = n.driveUUID;
  }

  void select() {
    this.selected = true;
  }

  void unSelect() {
    this.selected = false;
  }

  void toggleSelect() {
    this.selected = !this.selected;
  }
}

class DirPath {
  String uuid;
  String name;
  int mtime;
  DirPath(this.uuid, this.name, this.mtime);
  DirPath.fromMap(Map m) {
    this.mtime = m['mtime'];
    this.name = m['name'];
    this.uuid = m['uuid'];
  }
}

class Node {
  String name;
  String driveUUID;
  String dirUUID;
  String tag;
  Node({this.name, this.driveUUID, this.dirUUID, this.tag});
}

/// update Selection, and refresh(setState)
class Select {
  Function update;
  Select(this.update);
  List<Entry> selectedEntry = [];

  toggleSelect(Entry entry) {
    if (entry.selected) {
      entry.unSelect();
      selectedEntry.remove(entry);
    } else {
      entry.select();
      selectedEntry.add(entry);
    }
    this.update();
  }

  clearSelect() {
    for (Entry entry in selectedEntry) {
      entry.unSelect();
    }
    selectedEntry.clear();
    this.update();
  }

  selectAll(List<Entry> entries) {
    for (Entry entry in entries) {
      entry.select();
      selectedEntry.add(entry);
    }
    this.update();
  }

  bool selectMode() => selectedEntry.length != 0;
}

class Config {
  bool gridView = false;
  bool selectMode = false;

  Config({this.gridView, this.selectMode});
  Config.combine(Config oldConfig, Config newConfig) {
    this.gridView = newConfig.gridView ?? oldConfig.gridView;
    this.selectMode = newConfig.selectMode ?? oldConfig.selectMode;
  }
}

// actions
class LoginAction {
  final Account data;
  LoginAction(this.data);
}

class DeviceLoginAction {
  final Device data;
  DeviceLoginAction(this.data);
}

class UpdateUserAction {
  final User data;
  UpdateUserAction(this.data);
}

class UpdateDrivesAction {
  final List<Drive> data;
  UpdateDrivesAction(this.data);
}

class UpdateApisAction {
  final Apis data;
  UpdateApisAction(this.data);
}

class UpdateConfigAction {
  final Config data;
  UpdateConfigAction(this.data);
}

final deviceLoginReducer = combineReducers<Device>([
  TypedReducer<Device, DeviceLoginAction>((data, action) => action.data),
]);

final accountLoginReducer = combineReducers<Account>([
  TypedReducer<Account, LoginAction>((data, action) => action.data),
]);

final updateUserReducer = combineReducers<User>([
  TypedReducer<User, UpdateUserAction>((data, action) => action.data),
]);

final updateDriveReducer = combineReducers<List<Drive>>([
  TypedReducer<List<Drive>, UpdateDrivesAction>((data, action) => action.data),
]);

final updateApisReducer = combineReducers<Apis>([
  TypedReducer<Apis, UpdateApisAction>((data, action) => action.data),
]);

// combine config
final updateConfigReducer = combineReducers<Config>([
  TypedReducer<Config, UpdateConfigAction>(
    (oldConfig, action) => Config.combine(oldConfig, action.data),
  ),
]);

AppState appReducer(AppState state, action) {
  return AppState(
    account: accountLoginReducer(state.account, action),
    device: deviceLoginReducer(state.device, action),
    localUser: updateUserReducer(state.localUser, action),
    drives: updateDriveReducer(state.drives, action),
    apis: updateApisReducer(state.apis, action),
    config: updateConfigReducer(state.config, action),
  );
}

AppState fakeState = AppState(
  account: Account(
    token:
        '1@eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpZCI6IjY5NDc2NjdhLWY4ZmYtNDk4Yy1iMGNiLWViYzRkOTc3MTVkNyIsInBhc3N3b3JkIjoiKjg0QUFDMTJGNTRBQjY2NkVDRkMyQTgzQzY3NjkwOEM4QkJDMzgxQjEiLCJjbGllbnRJZCI6ImZsdXR0ZXJfVGVzdCIsInR5cGUiOiJBbmRyb2lkIn0.kiODgW5nfxnQylcUSgRHChEA8DV8SzL7FCkQ115tDBo',
    nickName: '斯德哥尔摩',
    username: '18817301665',
    avatarUrl:
        "https://wisnuc.s3.cn-north-1.amazonaws.com.cn/avatar/8a35501b-4d99-4830-95b8-649233d59658",
    id: "6947667a-f8ff-498c-b0cb-ebc4d97715d7",
    mail: "xu.kang@winsuntech.cn",
  ),
  device: Device(deviceName: 'Fake winas'),
  localUser: null,
  drives: [
    Drive(tag: 'home', uuid: "15a5b6d7-74da-4a0f-bdd7-64ecad6498aa"),
    Drive(tag: 'built-in', uuid: "6afcf55e-8482-4542-a33d-4791a7277f96"),
    Drive(
      type: 'backup',
      uuid: "9e85bff6-1cf4-429f-a2c2-6c11e0913ab4",
      client: DriveClient(type: 'iOS'),
      label: "iPhone 8",
    ),
    Drive(
      type: 'backup',
      uuid: "860688ed-7a83-45b3-9d67-aee517e2b7e2",
      client: DriveClient(type: 'Android'),
      label: "lxw-PC",
    ),
  ],
  apis: new Apis(
      '0@eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpZCI6IjY5NDc2NjdhLWY4ZmYtNDk4Yy1iMGNiLWViYzRkOTc3MTVkNyIsInBhc3N3b3JkIjoiKjg0QUFDMTJGNTRBQjY2NkVDRkMyQTgzQzY3NjkwOEM4QkJDMzgxQjEiLCJjbGllbnRJZCI6ImZsdXR0ZXJfVGVzdCIsInR5cGUiOiJBbmRyb2lkIn0.9cwn6OHlNfwQAQR7DciV9E2DPIcl-yWGBfvpdWUluaM',
      "10.10.9.234",
      'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJ1dWlkIjoiY2NmMmJlYzQtOTk2ZC00OTUyLTllNmMtZjRmOTBiNjBkODEwIiwid2luYXNVc2VySWQiOiI2OTQ3NjY3YS1mOGZmLTQ5OGMtYjBjYi1lYmM0ZDk3NzE1ZDciLCJ0aW1lc3RhbXAiOjE1NDgyMjU0ODI2NzB9.qYZv8CyLUxxNu0UrMsx7Y-4wkhW64sv1cE5Qu2JYJus',
      "6947667a-f8ff-498c-b0cb-ebc4d97715d7",
      false,
      "test_b44-a529-4dcf-aa30-240a151d8e03",
      'cookie'),
  config: Config(gridView: true, selectMode: false),
);

class AppState {
  final Account account;
  final Device device;
  final User localUser;
  final List<Drive> drives;
  final Apis apis;
  final Config config;
  AppState({
    this.account,
    this.device,
    this.localUser,
    this.drives,
    this.apis,
    this.config,
  });

  factory AppState.initial() => new AppState(
      account: null,
      device: null,
      localUser: null,
      drives: [],
      apis: null,
      config: null);

  factory AppState.autologin() => fakeState;
}
