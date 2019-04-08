import 'dart:typed_data';
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:flutter_redux/flutter_redux.dart';

import '../redux/redux.dart';

const double _kMinFlingVelocity = 800.0;

class DevicePhotoViewer extends StatefulWidget {
  const DevicePhotoViewer({Key key, this.entity, this.thumbData, this.list})
      : super(key: key);
  final Uint8List thumbData;
  final List list;
  final AssetEntity entity;

  @override
  _DevicePhotoViewerState createState() => _DevicePhotoViewerState();
}

class _DevicePhotoViewerState extends State<DevicePhotoViewer> {
  /// current photo, default: widget.photo
  AssetEntity currentItem;
  ScrollController myScrollController = ScrollController();

  @override
  void initState() {
    currentItem = widget.entity;
    super.initState();
  }

  double opacity = 1.0;
  updateOpacity(double value) {
    setState(() {
      opacity = value.clamp(0.0, 1.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    print('currentItem ${currentItem.id}');
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          '照片',
          style: TextStyle(
            color: Color.fromARGB((opacity * 255 * 0.87).round(), 0, 0, 0),
            fontWeight: FontWeight.normal,
          ),
        ),
        elevation: 0.0,
        brightness: Brightness.light,
        bottomOpacity: opacity,
        toolbarOpacity: opacity,
        backgroundColor: Color.fromARGB((opacity * 255).round(), 255, 255, 255),
        iconTheme: IconThemeData(color: Colors.black38),
      ),
      body: PageView.builder(
        controller:
            PageController(initialPage: widget.list.indexOf(currentItem)),
        itemBuilder: (context, position) {
          final photo = widget.list[position] as AssetEntity;
          return GridPhoto(
            updateOpacity: updateOpacity,
            photo: photo,
            thumbData: photo == widget.entity ? widget.thumbData : null,
          );
        },
        itemCount: widget.list.length,
        onPageChanged: (int index) {
          print('current index $index');
          if (mounted) {
            setState(() {
              currentItem = widget.list[index];
            });
          }
        },
      ),
    );
  }
}

class GridPhoto extends StatefulWidget {
  const GridPhoto({Key key, this.photo, this.thumbData, this.updateOpacity})
      : super(key: key);
  final Uint8List thumbData;
  final AssetEntity photo;
  final Function updateOpacity;

  @override
  _GridPhotoState createState() => _GridPhotoState();
}

class _GridPhotoState extends State<GridPhoto>
    with SingleTickerProviderStateMixin {
  AnimationController _controller;
  Animation<Offset> _flingAnimation;
  Animation<double> _scaleAnimation;
  Offset _offset = Offset.zero;
  double _scale = 1.0;
  Offset _normalizedOffset;
  double _previousScale;
  VideoPlayerController videoPlayerController;
  ChewieController chewieController;
  Widget playerWidget;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this)
      ..addListener(_handleFlingAnimation);
    thumbData = widget.thumbData;
  }

  @override
  void dispose() {
    _controller?.dispose();
    videoPlayerController?.pause();
    videoPlayerController?.dispose();
    chewieController?.dispose();
    super.dispose();
  }

  // The maximum offset value is 0,0. If the size of this renderer's box is w,h
  // then the minimum offset value is w - _scale * w, h - _scale * h.
  Offset _clampOffset(Offset offset) {
    final Size size = context.size;
    final Offset minOffset = Offset(size.width, size.height) * (1.0 - _scale);
    return Offset(
        offset.dx.clamp(minOffset.dx, 0.0), offset.dy.clamp(minOffset.dy, 0.0));
  }

  void _handleFlingAnimation() {
    setState(() {
      _offset = _flingAnimation.value;
      _scale = _scaleAnimation.value;
    });
  }

  double opacity = 1;

  updateOpacity() {
    widget.updateOpacity(opacity);
  }

  Offset prevPosition;

  void _handleOnScaleStart(ScaleStartDetails details) {
    print('_handleOnScaleStart');
    opacity = 1;
    prevPosition = details.focalPoint;
    updateOpacity();
    setState(() {
      _previousScale = _scale;
      _normalizedOffset = (details.focalPoint - _offset) / _scale;
      // The fling animation stops if an input gesture starts.
      _controller.stop();
    });
  }

  void _handleOnScaleUpdate(ScaleUpdateDetails details) {
    print('_handleOnScaleUpdate ${details.scale}');
    if (_scale == 1.0 && details.scale == 1.0) {
      final rate = 255;

      Offset delta = details.focalPoint - prevPosition;
      prevPosition = details.focalPoint;
      print(delta);
      print(details.focalPoint);

      _offset += delta;

      opacity = (1 - _offset.dy / rate).clamp(0.0, 1.0);

      updateOpacity();
      setState(() {});
    } else {
      setState(() {
        _scale = (_previousScale * details.scale).clamp(1.0, 4.0);
        // Ensure that image location under the focal point stays in the same place despite scaling.
        _offset = _clampOffset(details.focalPoint - _normalizedOffset * _scale);
      });
    }
  }

  void _handleOnScaleEnd(ScaleEndDetails details) {
    if (opacity <= 0.5) {
      Navigator.pop(context);
      return;
    }
    _scaleAnimation =
        _controller.drive(Tween<double>(begin: _scale, end: _scale));
    final double magnitude = details.velocity.pixelsPerSecond.distance;

    if (_scale == 1.0) {
      // return to center
      _flingAnimation =
          _controller.drive(Tween<Offset>(begin: _offset, end: Offset(0, 0)));
    } else {
      // fling after move
      if (magnitude < _kMinFlingVelocity) return;
      final Offset direction = details.velocity.pixelsPerSecond / magnitude;
      final double distance = (Offset.zero & context.size).shortestSide;
      _flingAnimation = _controller.drive(Tween<Offset>(
          begin: _offset, end: _clampOffset(_offset + direction * distance)));
    }
    opacity = 1.0;
    updateOpacity();

    _controller
      ..value = 0.0
      ..fling(velocity: magnitude / 1000.0);
  }

  int lastTapTime = 0;

  /// milliseconds of double tap's delay
  final timeDelay = 300;

  /// scale rate when double tap
  final scaleRate = 2.0;

  void handleTapUp(TapUpDetails event) {
    final tapTime = DateTime.now().millisecondsSinceEpoch;
    if (tapTime - lastTapTime < timeDelay) {
      double scaleEnd;
      Offset offsetEnd;
      if (_scale == 1.0) {
        scaleEnd = 4.0;
        offsetEnd = event.globalPosition * scaleEnd / -2;
      } else {
        scaleEnd = 1.0;
        offsetEnd = Offset(0, 0);
      }

      _flingAnimation =
          _controller.drive(Tween<Offset>(begin: _offset, end: offsetEnd));

      _scaleAnimation =
          _controller.drive(Tween<double>(begin: _scale, end: scaleEnd));

      _controller
        ..value = 0.0
        ..fling(velocity: 1.0);
    }
    lastTapTime = tapTime;
  }

  Uint8List imageData;
  Uint8List thumbData;

  _getPhoto(AppState state) async {
    // download thumb
    if (thumbData == null) {
      thumbData = await widget.photo.thumbDataWithSize(200, 200);
    }
    if (thumbData != null && this.mounted) {
      print('thumbData updated');
      await Future.delayed(Duration.zero);
      setState(() {});
    } else {
      return;
    }
    // is video
    if (widget.photo.type == AssetType.video) {
      final file = await widget.photo.file;
      final size = await widget.photo.size;

      videoPlayerController = VideoPlayerController.file(file);

      print('aspectRatio ${size.toString()}');

      chewieController = ChewieController(
        videoPlayerController: videoPlayerController,
        aspectRatio: size.aspectRatio,
        autoPlay: true,
        looping: true,
      );

      playerWidget = Chewie(
        controller: chewieController,
      );

      if (this.mounted) {
        print('video updated');
        setState(() {});
      }
    } else if (widget.photo.type == AssetType.image) {
      final file = await widget.photo.file;
      imageData = await file.readAsBytes();

      if (imageData != null && this.mounted) {
        print('imageData updated');
        setState(() {});
      }
    }
    print('refresh success');
  }

  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, AppState>(
      onInit: (store) => _getPhoto(store.state),
      onDispose: (store) => {},
      converter: (store) => store.state,
      builder: (context, state) {
        return Container(
            color: Color.fromARGB((opacity * 255).round(), 255, 255, 255),
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: thumbData == null
                      ? Center(child: CircularProgressIndicator())
                      : playerWidget != null
                          ? Container()
                          : GestureDetector(
                              onScaleStart: _handleOnScaleStart,
                              onScaleUpdate: _handleOnScaleUpdate,
                              onScaleEnd: _handleOnScaleEnd,
                              onTapUp: handleTapUp,
                              child: ClipRect(
                                child: Transform(
                                  transform: Matrix4.identity()
                                    ..translate(_offset.dx, _offset.dy)
                                    ..scale(_scale),
                                  child: Image.memory(
                                    thumbData,
                                    fit: BoxFit.contain,
                                    gaplessPlayback: true,
                                  ),
                                ),
                              ),
                            ),
                ),
                Positioned.fill(
                  child: thumbData == null && imageData == null
                      ? Center(child: CircularProgressIndicator())
                      : playerWidget != null
                          ? playerWidget
                          : GestureDetector(
                              onScaleStart: _handleOnScaleStart,
                              onScaleUpdate: _handleOnScaleUpdate,
                              onScaleEnd: _handleOnScaleEnd,
                              onTapUp: handleTapUp,
                              child: ClipRect(
                                child: Transform(
                                  transform: Matrix4.identity()
                                    ..translate(_offset.dx, _offset.dy)
                                    ..scale(_scale),
                                  child: Image.memory(
                                    imageData ?? thumbData,
                                    fit: BoxFit.contain,
                                    gaplessPlayback: true,
                                  ),
                                ),
                              ),
                            ),
                ),
                imageData == null && playerWidget == null
                    ? Center(child: CircularProgressIndicator())
                    : Container(),
              ],
            ));
      },
    );
  }
}