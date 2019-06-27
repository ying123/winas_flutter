import '../common/utils.dart';

class Info {
  String bleAddr;
  String eccName;
  String ssid;
  String sn;
  String cert;
  String address;
  String macAddress;

  String fingerprint;
  String signer;
  String certNotBefore;
  String certNotAfter;
  Info.fromMap(Map m) {
    final device = m['device'];
    final net = m['net'];

    this.eccName = device['ecc'];
    final ble = m['ble'];
    final unknown = i18n('Unknown Status in Info');
    if (ble != null && ble['state'] == "Started") {
      bleAddr = ble['address'];
    } else {
      bleAddr = unknown;
    }
    this.sn = device['sn'];
    this.cert = device['cert'];
    if (net != null && net['state'] == 70 && net['detail'] != null) {
      final interface = net['addresses'][0];
      this.address = interface['address'];
      final detail = net['detail'];
      this.macAddress = detail['HwAddress'];
      this.ssid = detail['Ssid'];
    } else {
      this.address = unknown;
      this.macAddress = unknown;
      this.ssid = unknown;
    }

    this.fingerprint = device['fingerprint'];
    this.signer = device['signer'];
    this.certNotBefore = prettyDate(device['notBefore']);
    this.certNotAfter = prettyDate(device['notAfter']);
  }
}
