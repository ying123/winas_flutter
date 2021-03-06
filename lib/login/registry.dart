import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';

import './stationLogin.dart';
import '../redux/redux.dart';
import '../common/utils.dart';
import '../common/request.dart';

class Registry extends StatefulWidget {
  Registry({Key key, this.wechat}) : super(key: key);

  /// Wechat token for binding
  final String wechat;
  @override
  _RegistryState createState() => _RegistryState();
}

class _RegistryState extends State<Registry> {
  String _status = 'phoneNumber';
  bool showPwd = true;

  ///  used in bind wechat
  ///
  ///  if (_userExist) -> login and bind
  ///
  ///  else -> registry and bind
  bool _userExist = false;

  // Focus action
  FocusNode focusNode1;
  FocusNode focusNode2;

  var request = Request();

  @override
  void initState() {
    super.initState();

    focusNode1 = FocusNode();
    focusNode2 = FocusNode();
  }

  @override
  void dispose() {
    // Clean up the focus node when the Form is disposed
    focusNode1.dispose();
    focusNode2.dispose();
    _count = -1;

    super.dispose();
  }

  String _phoneNumber = '';

  String _code = '';

  String _password = '';

  String _error;

  String _ticket;

  LoadingInstance _loadingInstance;

  /// show loading
  _loading(BuildContext ctx) {
    _loadingInstance = showLoading(ctx);
  }

  /// close loading
  _loadingOff() {
    _loadingInstance.close();
  }

  /// close loading, setState and focus node
  _nextPage(BuildContext context, String status, FocusNode node) {
    _loadingOff();
    setState(() {
      _status = status;
    });

    var future = Future.delayed(const Duration(milliseconds: 100),
        () => FocusScope.of(context).requestFocus(node));
    future.then((res) => print('100ms later'));
  }

  /// handle SmsError: close loading, setState
  _handleSmsError(BuildContext context, DioError error) {
    _loadingOff();
    debug(error.response.data);
    if ([60702, 60003].contains(error.response.data['code'])) {
      showSnackBar(context, i18n('Request Verification Code Too Frquent'));
    } else {
      showSnackBar(context, i18n('Request Verification Code Failed'));
    }
    setState(() {});
  }

  /// nextStep for normal register
  _nextStep(BuildContext context, store) async {
    if (_status == 'phoneNumber') {
      // check phoneNumber
      if (_phoneNumber.length != 11 || !_phoneNumber.startsWith('1')) {
        setState(() {
          _error = i18n('Invalid Phone Number');
        });
        return;
      }

      // request smsCode
      _loading(context);

      try {
        await request.req('smsCode', {
          'type': 'register',
          'phone': _phoneNumber,
        });
      } catch (error) {
        if (error.response.data['code'] == 60001) {
          _loadingOff();
          showSnackBar(context, i18n('Phone Number Already Registered'));
          setState(() {});
          return;
        }
        _handleSmsError(context, error);
        return;
      }
      _startCount();
      // show next page
      _nextPage(context, 'code', focusNode1);
    } else if (_status == 'code') {
      // check code
      if (_code.length != 4) {
        setState(() {
          _error = i18n('Verification Code Length Not Match Error');
        });
        return;
      }

      // request smsTicket via code
      _ticket = null;
      _loading(context);
      try {
        var res = await request.req('smsTicket', {
          'code': _code,
          'phone': _phoneNumber,
          'type': 'register',
        });

        _ticket = res.data;
        if (_ticket == null) {
          throw Error();
        }
      } catch (error) {
        _loadingOff();
        setState(() {
          _error = i18n('Verification Code Error');
        });
        return;
      }

      // show next page
      _nextPage(context, 'password', focusNode2);
    } else if (_status == 'password') {
      // check password
      if (_password.length <= 7) {
        setState(() {
          _error = i18n('Password Too Short Error');
        });
        return;
      }

      String clientId = await getClientId();

      // register with _code, _phoneNumber, _ticket
      _loading(context);
      try {
        await request.req('registry', {
          'code': _code,
          'phone': _phoneNumber,
          "ticket": _ticket,
          'clientId': clientId,
          "password": _password,
        });
      } catch (error) {
        _loadingOff();
        setState(() {
          _error = i18n('Sign Up Failed');
        });
        return;
      }

      // show next page
      _loadingOff();
      setState(() {
        _status = 'success';
      });
    } else {
      // return to login: remove all router, and push '/login'
      Navigator.pushNamedAndRemoveUntil(
          context, '/login', (Route<dynamic> route) => false);
    }
  }

  /// nextStep for wechat
  _wechatNextStep(BuildContext context, store) async {
    if (_status == 'phoneNumber') {
      // check phoneNumber
      if (_phoneNumber.length != 11 || !_phoneNumber.startsWith('1')) {
        setState(() {
          _error = i18n('Invalid Phone Number');
        });
        return;
      }

      // get smsCode ->
      // 1. user already exist
      // 2. new user, need register
      _loading(context);
      _userExist = false;
      try {
        await request.req('smsCode', {
          'type': 'register',
          'phone': _phoneNumber,
        });
      } catch (error) {
        if (error.response.data['code'] == 60001) {
          // user already exist
          // request code to login & bind wechat
          try {
            await request.req('smsCode', {
              'type': 'login',
              'phone': _phoneNumber,
            });
          } catch (err) {
            _handleSmsError(context, err);
            return;
          }
          _userExist = true;
          // show next page
          _nextPage(context, 'code', focusNode1);
          return;
        } else {
          // request register smsCode error
          _handleSmsError(context, error);
          return;
        }
      }
      _startCount();
      // _phoneNumber is new, need to register account
      // show next page
      _nextPage(context, 'code', focusNode1);
    } else if (_status == 'code') {
      if (_code.length != 4) {
        setState(() {
          _error = i18n('Verification Code Length Not Match Error');
        });
        return;
      }

      // _userExist == true, login via code, bind wechat, login station
      if (_userExist) {
        _loading(context);
        // get token
        var res;
        try {
          String clientId = await getClientId();
          res = await request.req('smsToken', {
            'code': _code,
            'phone': _phoneNumber,
            'clientId': clientId,
          });
        } catch (err) {
          debug(err);
          showSnackBar(context, i18n('Verification Code Error'));
          return;
        }
        // bind wechat with account
        try {
          await request.req('bindWechat', {
            "wechatToken": widget.wechat,
          });
        } catch (err) {
          debug(err);
          _loadingOff();
          showSnackBar(context, i18n('Bind WeChat Failed'));
          return;
        }

        // update Account
        Account account = Account.fromMap(res.data);
        store.dispatch(LoginAction(account));

        // device login
        try {
          await deviceLogin(context, request, account, store);
        } catch (e) {
          debug(e);
          _loadingOff();
          showSnackBar(context, i18n('Login Failed'));
          return;
        }
      } else {
        // request smsTicket via code
        _ticket = null;
        _loading(context);
        try {
          var res = await request.req('smsTicket', {
            'code': _code,
            'phone': _phoneNumber,
            'type': 'register',
          });

          _ticket = res.data;
        } catch (error) {
          _loadingOff();
          debug(error);
          showSnackBar(context, i18n('Verification Code Error'));
          return;
        }

        // show next page
        _nextPage(context, 'password', focusNode2);
      }
    } else if (_status == 'password') {
      // register with _code, _phoneNumber, _ticket
      if (_password.length <= 7) {
        setState(() {
          _error = i18n('Password Too Short Error');
        });
        return;
      }
      _loading(context);

      try {
        String clientId = await getClientId();
        // registry
        await request.req('registry', {
          'code': _code,
          'phone': _phoneNumber,
          "ticket": _ticket,
          'clientId': clientId,
          "password": _password,
        });

        // bind wechat with account
        await request.req('bindWechat', {
          "wechatToken": widget.wechat,
        });
      } catch (error) {
        _loadingOff();
        debug(error);
        showSnackBar(context, i18n('Sign Up Failed'));
        return;
      }

      // show next page
      _loadingOff();
      setState(() {
        _status = 'success';
      });
    } else {
      // return to login: remove all router, and push '/login'
      Navigator.pushNamedAndRemoveUntil(
          context, '/login', (Route<dynamic> route) => false);
    }
  }

  int _count = -1;

  _countDown() async {
    if (_count > 0 && this.mounted) {
      await Future.delayed(Duration(seconds: 1));
      if (this.mounted) {
        setState(() {
          _count -= 1;
        });
        await _countDown();
      }
    }
  }

  /// start count down of 60 seconds
  _startCount() {
    _count = 60;
    _countDown().catchError(print);
  }

  /// resendSmg
  _resendSmg(BuildContext ctx) async {
    _loading(ctx);
    try {
      await request.req('smsCode', {
        'type': 'password',
        'phone': _phoneNumber,
      });
    } catch (error) {
      _handleSmsError(ctx, error);
      return;
    }
    _startCount();
    _loadingOff();
    showSnackBar(ctx, i18n('Send Verification Code Success'));
  }

  List<Widget> renderPage() {
    switch (_status) {
      case 'phoneNumber':
        return <Widget>[
          Text(
            i18n('Bind Phone Number Title'),
            textAlign: TextAlign.left,
            style: TextStyle(fontSize: 28.0, color: Colors.white),
          ),
          Container(height: 16.0),
          Text(
            i18n('Bind Phone Number Text'),
            style: TextStyle(color: Colors.white),
          ),
          Container(height: 32.0),
          TextField(
            key: Key('phoneNumber'),
            onChanged: (text) {
              setState(() => _error = null);
              _phoneNumber = text;
            },
            // controller: TextEditingController(text: _phoneNumber),
            autofocus: true,
            decoration: InputDecoration(
                labelText: i18n('Phone Number'),
                labelStyle: TextStyle(
                  fontSize: 21,
                  color: Colors.white,
                  height: 0.8,
                ),
                prefixIcon: Icon(Icons.person, color: Colors.white),
                errorText: _error),
            style: TextStyle(fontSize: 24, color: Colors.white),
            maxLength: 11,
            keyboardType: TextInputType.number,
          ),
        ];

      case 'code':
        return <Widget>[
          Text(
            i18n('Verification Code Input Text'),
            textAlign: TextAlign.left,
            style: TextStyle(fontSize: 28.0, color: Colors.white),
          ),
          Container(height: 16.0),
          Text(
            i18n(
              'Verification Code Has Sent Text',
              {'phoneNumber': _phoneNumber},
            ),
            style: TextStyle(color: Colors.white),
          ),
          Container(height: 32.0),
          TextField(
            key: Key('code'),
            onChanged: (text) {
              setState(() => _error = null);
              _code = text;
            },
            // controller: TextEditingController(text: _phoneNumber),
            focusNode: focusNode1,
            decoration: InputDecoration(
                labelText: i18n('Verification Code Input Text'),
                labelStyle: TextStyle(
                  fontSize: 21,
                  color: Colors.white,
                  height: 0.8,
                ),
                prefixIcon: Icon(Icons.verified_user, color: Colors.white),
                errorText: _error),
            style: TextStyle(fontSize: 24, color: Colors.white),
            maxLength: 4,
            keyboardType: TextInputType.number,
          ),
        ];

      case 'password':
        return <Widget>[
          Text(
            i18n('Set Password'),
            textAlign: TextAlign.left,
            style: TextStyle(fontSize: 28.0, color: Colors.white),
          ),
          Container(height: 16.0),
          Text(
            i18n('Password Requirements'),
            style: TextStyle(color: Colors.white),
          ),
          Container(height: 32.0),
          TextField(
            key: Key('password'),
            onChanged: (text) {
              setState(() => _error = null);
              _password = text;
            },
            // controller: TextEditingController(text: _password),
            focusNode: focusNode2,
            decoration: InputDecoration(
                labelText: i18n('Password'),
                labelStyle: TextStyle(
                  fontSize: 21,
                  color: Colors.white,
                  height: 0.8,
                ),
                prefixIcon: Icon(Icons.lock, color: Colors.white),
                suffixIcon: IconButton(
                  icon: Icon(showPwd ? Icons.visibility : Icons.visibility_off,
                      color: Colors.white),
                  onPressed: () {
                    setState(() {
                      showPwd = !showPwd;
                    });
                  },
                ),
                errorText: _error),
            style: TextStyle(fontSize: 24, color: Colors.white),
            obscureText: showPwd,
          ),
        ];

      case 'success':
        return <Widget>[
          Text(
            i18n('Sign Up Success'),
            textAlign: TextAlign.left,
            style: TextStyle(fontSize: 28.0, color: Colors.white),
          ),
          Container(height: 16.0),
          Text(
            i18n('Welcoming Text'),
            style: TextStyle(color: Colors.white),
          ),
          Expanded(
            flex: 1,
            child: Center(
              child: Icon(Icons.check, color: Colors.white, size: 48),
            ),
          ),
          Expanded(
            flex: 1,
            child: Container(),
          ),
        ];

      default:
        return <Widget>[];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.teal,
      appBar: AppBar(
        elevation: 0.0, // no shadow
        actions: _status == 'code'
            ? <Widget>[
                Builder(builder: (BuildContext ctx) {
                  return FlatButton(
                    child: _count > 0
                        ? Text(i18nPlural('Resend Later', _count))
                        : Text(i18n('Resend')),
                    textColor: Colors.white,
                    onPressed: _count > 0 ? null : () => _resendSmg(ctx),
                  );
                }),
              ]
            : <Widget>[],
      ),
      floatingActionButton: Builder(
        builder: (ctx) {
          return StoreConnector<AppState, VoidCallback>(
            converter: (store) => () => widget.wechat == null
                ? _nextStep(ctx, store)
                : _wechatNextStep(ctx, store),
            builder: (context, callback) => FloatingActionButton(
              onPressed: callback,
              tooltip: i18n('Next Step'),
              backgroundColor: Colors.white70,
              elevation: 0.0,
              child: Icon(
                Icons.chevron_right,
                color: Colors.teal,
                size: 48,
              ),
            ),
          );
        },
      ),
      body: Theme(
        data: Theme.of(context).copyWith(
          primaryColor: Colors.white,
          accentColor: Colors.white,
          hintColor: Colors.white,
          brightness: Brightness.dark,
        ),
        child: Container(
          constraints: BoxConstraints.expand(),
          padding: EdgeInsets.all(16),
          color: Colors.teal,
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: renderPage()),
        ),
      ),
    );
  }
}
