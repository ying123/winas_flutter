import 'dart:async';
import 'dart:typed_data';
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:share_extend/share_extend.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:amap_base_map/amap_base_map.dart' as AMap;
import 'package:amap_base_search/amap_base_search.dart' as ASearch;

import '../redux/redux.dart';
import '../common/utils.dart';
import '../common/cache.dart';
import '../files/delete.dart';
import '../transfer/manager.dart';

const double _kMinFlingVelocity = 800.0;

const videoTypes = 'RM.RMVB.WMV.AVI.MP4.3GP.MKV.MOV.FLV.MPEG';

class PhotoViewer extends StatefulWidget {
  const PhotoViewer(
      {Key key, this.photo, this.thumbData, this.list, this.updateList})
      : super(key: key);
  final Uint8List thumbData;
  final List list;
  final Entry photo;
  final Function updateList;
  @override
  _PhotoViewerState createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  /// current photo, default: widget.photo
  Entry currentItem;
  ScrollController myScrollController = ScrollController();
  PageController pageController;

  @override
  void initState() {
    currentItem = widget.photo;
    pageController =
        PageController(initialPage: widget.list.indexOf(currentItem));
    super.initState();
  }

  double opacity = 1.0;
  updateOpacity(double value) {
    setState(() {
      opacity = value.clamp(0.0, 1.0);
    });
  }

  bool showTitle = true;
  void toggleTitle({bool show}) {
    if (show != null) {
      setState(() {
        showTitle = show;
      });
    } else {
      setState(() {
        showTitle = !showTitle;
      });
    }
  }

  void _share(BuildContext ctx, Entry entry, AppState state) async {
    final dialog = DownloadingDialog(ctx, entry.size);
    dialog.openDialog();

    final cm = await CacheManager.getInstance();
    String entryPath = await cm.getPhotoPath(entry, state,
        onProgress: dialog.onProgress, cancelToken: dialog.cancelToken);

    dialog.close();
    if (dialog.canceled) {
      showSnackBar(ctx, '下载已取消');
    } else if (entryPath == null) {
      showSnackBar(ctx, '下载失败');
    } else {
      try {
        ShareExtend.share(entryPath, "file");
      } catch (error) {
        print(error);
        showSnackBar(ctx, '分享失败');
      }
    }
  }

  void _download(BuildContext ctx, Entry entry, AppState state) async {
    final cm = TransferManager.getInstance();
    cm.newDownload(entry, state);
    showSnackBar(ctx, '该文件已加入下载任务');
  }

  void _delete(BuildContext ctx, Entry entry, AppState state) async {
    bool success = await showDialog(
      context: this.context,
      builder: (BuildContext context) => DeleteDialog(
            entries: [entry],
            isMedia: true,
          ),
    );

    if (success == true) {
      showSnackBar(ctx, '删除成功');
      final isFirstPage = pageController.offset == 0.0;

      // is not FirstPage: return to previousPage
      if (!isFirstPage) {
        pageController.previousPage(
            duration: Duration(milliseconds: 300), curve: Curves.ease);
      }

      setState(() {
        widget.list.remove(entry);
      });
      widget.updateList();

      // is FirstPage: return to list
      if (isFirstPage) {
        Navigator.pop(ctx);
      }
    } else if (success == false) {
      showSnackBar(ctx, '删除失败');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: PageView.builder(
              controller: pageController,
              itemBuilder: (context, position) {
                final photo = widget.list[position];

                final view = GridPhoto(
                  updateOpacity: updateOpacity,
                  photo: photo,
                  thumbData: photo == widget.photo ? widget.thumbData : null,
                  toggleTitle: toggleTitle,
                  showTitle: showTitle,
                );
                return Container(child: view);
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
          ),
          // title
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: showTitle
                ? Material(
                    color: Color.fromARGB(240, 255, 255, 255),
                    elevation: 2.0,
                    child: SafeArea(
                      child: StoreConnector<AppState, AppState>(
                        converter: (store) => store.state,
                        builder: (context, state) {
                          return Container(
                            color: Colors.transparent,
                            padding: EdgeInsets.only(top: 4, bottom: 4),
                            child: Row(
                              children: <Widget>[
                                Container(width: 4),
                                IconButton(
                                  icon: Icon(Icons.close),
                                  onPressed: () {
                                    Navigator.pop(context);
                                  },
                                ),
                                Container(width: 16),
                                Expanded(flex: 1, child: Container()),
                                IconButton(
                                  icon: Icon(Icons.share),
                                  onPressed: () =>
                                      _share(context, currentItem, state),
                                ),
                                IconButton(
                                  icon: Icon(Icons.file_download),
                                  onPressed: () =>
                                      _download(context, currentItem, state),
                                ),
                                IconButton(
                                  icon: Icon(Icons.delete),
                                  onPressed: () =>
                                      _delete(context, currentItem, state),
                                )
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  )
                : Container(),
          ),
        ],
      ),
    );
  }
}

class GridPhoto extends StatefulWidget {
  const GridPhoto({
    Key key,
    this.photo,
    this.thumbData,
    this.updateOpacity,
    this.toggleTitle,
    this.showTitle,
  }) : super(key: key);
  final Uint8List thumbData;
  final Entry photo;
  final Function updateOpacity;
  final Function toggleTitle;
  final bool showTitle;

  @override
  _GridPhotoState createState() => _GridPhotoState();
}

class _GridPhotoState extends State<GridPhoto>
    with SingleTickerProviderStateMixin {
  AnimationController _controller;

  Animation<Offset> _flingAnimation;
  Animation<double> _scaleAnimation;
  Offset _offset = Offset.zero;
  ImageInfo info;
  double _scale = 1.0;
  Offset _normalizedOffset;
  double _previousScale;
  VideoPlayerController videoPlayerController;
  ChewieController chewieController;
  Widget playerWidget;
  bool showDetails = false;
  double detailTop = double.negativeInfinity;

  /// amap
  AMap.AMapController _aMapController;

  /// detail height
  /// with location: 160.0
  /// without location: 96
  double detailHeight = 96;
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
    chewieController?.pause();
    chewieController?.dispose();
    _aMapController?.dispose();
    super.dispose();
  }

  Size getTrueSize() {
    final clientW = context.size.width;
    final clientH = context.size.height;
    if (info is ImageInfo) {
      final w = info.image.width;
      final h = info.image.height;
      if (w / h > clientW / clientH) {
        return Size(clientW, h / w * clientW);
      }
      return Size(w / h * clientH, clientH);
    } else {
      return Size(clientW, clientH);
    }
  }

  /// top of detail widget
  double getDetailTop() {
    // hidden detail widget
    if (!showDetails && detailTop != double.negativeInfinity) {
      return double.infinity;
    }
    // move detail widget up
    if (_offset.dy >= detailTop) {
      // speed of detail widget appear
      final speed = 480;
      return 240 + speed * (1 - _offset.dy / detailTop);
    } else {
      // move detail widget over maxtop
      return 480 - (_offset.dy / detailTop) * 240;
    }
  }

  // keep value in maximum and minimum offset value
  Offset _clampOffset(Offset offset) {
    final Size size = getTrueSize();

    double maxDx =
        context.size.width - (context.size.width + size.width) / 2 * _scale;

    double minDx = (size.width - context.size.width) / 2 * _scale;

    // keep min < max
    if (maxDx < minDx) {
      final tmp = maxDx;
      maxDx = minDx;
      minDx = tmp;
    }

    // max dy = H - (H + h) / 2 * scale
    double maxDy =
        context.size.height - (context.size.height + size.height) / 2 * _scale;
    // min dy
    double minDy = (size.height - context.size.height) / 2 * _scale;

    if (maxDy < minDy) {
      final tmp = maxDy;
      maxDy = minDy;
      minDy = tmp;
    }

    final res =
        Offset(offset.dx.clamp(minDx, maxDx), offset.dy.clamp(minDy, maxDy));
    return res;
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
    opacity = 1;
    prevPosition = details.focalPoint;

    // toggle title
    canceled = true;
    // widget.toggleTitle(show: false);

    // update opacity
    updateOpacity();
    setState(() {
      _previousScale = _scale;
      _normalizedOffset = (details.focalPoint - _offset) / _scale;
      // The fling animation stops if an input gesture starts.
      _controller.stop();
    });
  }

  void _handleOnScaleUpdate(ScaleUpdateDetails details) {
    if (_scale == 1.0 && details.scale == 1.0) {
      /// rate of downScale to close viewer
      final rate = 255;

      Offset delta = details.focalPoint - prevPosition;
      prevPosition = details.focalPoint;
      if (delta.dy < 0 && _offset.dy == 0) {
        setState(() {
          showDetails = true;
        });
      }

      _offset += delta;

      // prevent move vertically when drag up
      if (_offset.dy < 0 && showDetails) {
        _offset = Offset(0.0, _offset.dy);
      }

      opacity = (1 - _offset.dy / rate).clamp(0.0, 1.0);

      updateOpacity();
      setState(() {});
    } else {
      setState(() {
        _scale = (_previousScale * details.scale).clamp(1.0, 4.0);
        // Ensure that image location under the focal point stays in the same place despite scaling.
        _offset = _clampOffset(details.focalPoint - _normalizedOffset * _scale);
        showDetails = false;
      });
    }
  }

  void _handleOnScaleEnd(ScaleEndDetails details) {
    /// dy > 0: drag down
    /// dy < 0: drag up
    final dy = details.velocity.pixelsPerSecond.dy;

    // drag image down, discard image view
    if (opacity <= 0.8 && dy > 0) {
      Navigator.pop(context);
      return;
    }

    _scaleAnimation =
        _controller.drive(Tween<double>(begin: _scale, end: _scale));
    final double magnitude = details.velocity.pixelsPerSecond.distance;

    // drag image up, show image detail
    if (_offset.dy < 0.0 && _scale == 1.0 && dy <= 0.0) {
      final Size size = getTrueSize();
      final bottomHeight = (context.size.height - size.height) / 2;
      final deltaH = (context.size.height - 240.0 - bottomHeight) * -1;
      _flingAnimation = _controller
          .drive(Tween<Offset>(begin: _offset, end: Offset(0, deltaH)));

      // show title
      widget.toggleTitle(show: true);

      setState(() {
        detailTop = deltaH;
        showDetails = true;
      });
    } else if (_scale == 1.0) {
      // return to center
      _flingAnimation =
          _controller.drive(Tween<Offset>(begin: _offset, end: Offset(0, 0)));

      setState(() {
        detailTop = double.negativeInfinity;
        showDetails = false;
      });
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

  /// on Horizontal Drag Start
  void handleHDragStart(DragStartDetails detail) {
    opacity = 1;

    // toggle title
    canceled = true;
    widget.toggleTitle(show: false);

    // update opacity
    updateOpacity();
    setState(() {
      _previousScale = _scale;
      prevPosition = detail.globalPosition;
      _controller.stop();
    });
  }

  /// on Horizontal Drag Update
  void handleHDragUpdate(DragUpdateDetails details) {
    Offset delta = details.globalPosition - prevPosition;

    // quick fix bug of Twofingers drag which not recognized as scale
    if (delta.distance > 32) delta = Offset(0, 0);
    prevPosition = details.globalPosition;

    setState(() {
      // Ensure that image location under the focal point stays in the same place despite scaling.
      _offset = _clampOffset(_offset + delta);
    });
  }

  /// on Horizontal Drag End
  void handleHDragEnd(DragEndDetails detail) {
    if (opacity <= 0.8) {
      Navigator.pop(context);
      return;
    }
    _scaleAnimation =
        _controller.drive(Tween<double>(begin: _scale, end: _scale));
    final double magnitude = detail.velocity.pixelsPerSecond.distance;

    if (_scale == 1.0) {
      // return to center
      _flingAnimation =
          _controller.drive(Tween<Offset>(begin: _offset, end: Offset(0, 0)));
    } else {
      // fling after move
      if (magnitude < _kMinFlingVelocity) return;
      final Offset direction = detail.velocity.pixelsPerSecond / magnitude;
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

  /// on Detail Vertical Drag Start
  void onDetailVerticalDragStart(DragStartDetails detail) {
    opacity = 1;

    // toggle title
    canceled = true;

    // update opacity
    updateOpacity();
    setState(() {
      _previousScale = _scale;
      prevPosition = detail.globalPosition;
      _controller.stop();
    });
  }

  /// on Detail Vertical Drag Update
  void onDetailVerticalDragUpdate(DragUpdateDetails details) {
    Offset delta = details.globalPosition - prevPosition;

    // quick fix bug of Twofingers drag which not recognized as scale
    if (delta.distance > 32) delta = Offset(0, 0);
    prevPosition = details.globalPosition;
    setState(() {
      // Ensure that image location under the focal point stays in the same place despite scaling.
      _offset = _offset + Offset(0, delta.dy);
    });
  }

  /// on Detail Vertical Drag End
  void onDetailVerticalDragEnd(DragEndDetails details) {
    /// dy > 0: drag down
    /// dy < 0: drag up
    // final dy = details.velocity.pixelsPerSecond.dy;

    final double magnitude = details.velocity.pixelsPerSecond.distance;

    if (_offset.dy > detailTop) {
      // return to center
      _flingAnimation =
          _controller.drive(Tween<Offset>(begin: _offset, end: Offset(0, 0)));

      setState(() {
        detailTop = double.negativeInfinity;
        showDetails = false;
      });
    } else {
      // other position move detail
      final Size size = getTrueSize();
      final bottomHeight = (context.size.height - size.height) / 2;
      final maxHeight =
          (context.size.height - 240.0 - bottomHeight) * -1 - detailHeight;

      print('maxHeight $maxHeight $_offset');
      _flingAnimation = _controller.drive(
        Tween<Offset>(
          begin: _offset,
          end: maxHeight > _offset.dy
              ? Offset(0, maxHeight)
              : Offset(0, _offset.dy),
        ),
      );

      // show title
      widget.toggleTitle(show: true);
      setState(() {
        showDetails = true;
      });
    }
    opacity = 1.0;
    updateOpacity();

    _controller
      ..value = 0.0
      ..fling(velocity: magnitude / 1000.0);
  }

  Future<ImageInfo> _getImage(imageProvider) {
    final Completer completer = Completer<ImageInfo>();
    final ImageStream stream =
        imageProvider.resolve(const ImageConfiguration());
    final listener = (ImageInfo info, bool synchronousCall) {
      if (!completer.isCompleted) {
        completer.complete(info);
      }
    };
    stream.addListener(listener);
    completer.future.then((_) {
      stream.removeListener(listener);
    });
    return completer.future;
  }

  Uint8List imageData;
  Uint8List thumbData;

  _getPhoto(AppState state) async {
    final cm = await CacheManager.getInstance();

    // download thumb
    if (thumbData == null) {
      thumbData = await cm.getThumbData(widget.photo, state);
    }

    info = await _getImage(MemoryImage(thumbData));

    if (this.mounted) {
      print('thumbData updated');
      setState(() {});
    } else {
      return;
    }
    // is video
    final ext = widget.photo.metadata.type;
    if (videoTypes.split('.').contains(ext)) {
      final apis = state.apis;
      // preview video
      if (apis.isCloud) return;

      final key = await cm.getRandomKey(widget.photo, state);
      if (key == null) return;

      final String url =
          'http://${apis.lanIp}:3000/media/$key.${ext.toLowerCase()}';
      print('${widget.photo.name}');
      print('url: $url, $mounted');

      // keep singleton
      if (videoPlayerController != null) return;

      videoPlayerController = VideoPlayerController.network(url);
      double aspectRatio;
      final meta = widget.photo.metadata;
      if (meta.width != null && meta.height != null && meta.width != 0) {
        aspectRatio = meta.width / meta.height;
        if (meta.rot == 90) {
          aspectRatio = 1 / aspectRatio;
        }
      }
      print('aspectRatio $aspectRatio');
      chewieController = ChewieController(
        videoPlayerController: videoPlayerController,
        aspectRatio: aspectRatio,
        autoPlay: true,
        looping: false,
      );

      playerWidget = Chewie(
        controller: chewieController,
      );

      if (this.mounted) {
        setState(() {});
      }
    } else {
      // download raw photo
      imageData = await cm.getPhoto(widget.photo, state);
      info = await _getImage(MemoryImage(imageData));

      if (imageData != null && this.mounted) {
        print('imageData updated');
        setState(() {});
      }
    }
  }

  int lastTapTime = 0;

  /// milliseconds of double tap's delay
  final timeDelay = 300;

  /// scale rate when double tap
  final scaleRate = 2.0;

  /// whether background Color is red
  bool showBlack = false;

  /// handle double tap
  bool canceled = false;
  void handleTapUp(TapUpDetails event) {
    final tapTime = DateTime.now().millisecondsSinceEpoch;
    if (tapTime - lastTapTime < timeDelay) {
      canceled = true;
      widget.toggleTitle(show: false);
      double scaleEnd;
      Offset offsetEnd;
      if (_scale == 1.0) {
        scaleEnd = 2.0;
        offsetEnd = Offset(context.size.width / -2, context.size.height / -2);
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
    } else {
      canceled = false;
      Future.delayed(Duration(milliseconds: timeDelay))
          .then((v) => canceled ? null : widget.toggleTitle());
    }
    lastTapTime = tapTime;
  }

  Widget detailRow(Widget icon, String mainText, String subText) {
    return Container(
      padding: EdgeInsets.all(16),
      child: Row(
        children: <Widget>[
          icon,
          Container(width: 24),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(child: Text(mainText)),
              Container(height: 8),
              Container(
                child: Text(subText, style: TextStyle(color: Colors.black38)),
              )
            ],
          )
        ],
      ),
    );
  }

  String location = '';
  bool fired = false;
  Future searchReGeocode(GPSLoc loc) async {
    if (fired) return;
    fired = true;
    try {
      await Future.delayed(Duration(seconds: 2));
      final res = await ASearch.AMapSearch().searchReGeocode(
        ASearch.LatLng(30.9824, 120.3053),
        100,
        0,
        // LatLng(loc.latitude, loc.longitude),
        // 100,
        // 0,
      );
      location = res.regeocodeAddress.city;
      if (mounted && location != null) {
        setState(() {});
      }
    } catch (e) {
      print('searchReGeocode error $e');
    } finally {
      // fired = false;
    }
  }

  Widget renderDetail() {
    final photo = widget.photo;
    final metadata = photo.metadata;

    // fullDate
    final date = metadata.fullDate ?? prettyDate(photo.bctime ?? photo.mtime);
    final List<int> list = List.from(date
        .replaceAll(' ', '-')
        .replaceAll(':', '-')
        .split('-')
        .map((s) => int.parse(s)));

    // week day
    final weekday =
        getWeekday(DateTime(list[0], list[1], list[2], list[3], list[4]));

    // image pixel
    final pixel = getPixel(metadata.width * metadata.height);
    // image resolution
    final resolution = '${metadata.width} x ${metadata.height}';

    // image size
    final size = prettySize(photo.size);

    final rowList = [
      Container(
        margin: EdgeInsets.all(16),
        child: Text('详情', style: TextStyle(fontSize: 18)),
      ),
      detailRow(Icon(Icons.insert_drive_file), photo.name, size),
      detailRow(Icon(Icons.calendar_today), date, weekday),
      detailRow(Icon(Icons.image), pixel, resolution),
    ];
    if (metadata.model != null && metadata.make != null) {
      rowList.add(detailRow(Icon(Icons.camera), metadata.model, metadata.make));
    }
    if (metadata.gps != null) {
      final loc = convertGPS(metadata.gps);
      if (loc != null) {
        detailHeight = 400;
        searchReGeocode(loc).catchError(print);

        rowList
            .add(detailRow(Icon(Icons.location_on), location, loc.toString()));
        rowList.add(Flexible(
          child: AMap.AMapView(
            onAMapViewCreated: (controller) {
              _aMapController = controller;
            },
            amapOptions: AMap.AMapOptions(
              compassEnabled: false,
              zoomControlsEnabled: true,
              logoPosition: AMap.LOGO_POSITION_BOTTOM_CENTER,
              camera: AMap.CameraPosition(
                target: AMap.LatLng(loc.latitude, loc.longitude),
                zoom: 15,
              ),
            ),
          ),
        ));
      }
    } else {
      detailHeight = 96;
    }

    return GestureDetector(
      onVerticalDragStart: onDetailVerticalDragStart,
      onVerticalDragUpdate: onDetailVerticalDragUpdate,
      onVerticalDragEnd: onDetailVerticalDragEnd,
      child: Container(
        color: Colors.white,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rowList,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, AppState>(
      onInit: (store) => _getPhoto(store.state),
      onDispose: (store) => {},
      converter: (store) => store.state,
      builder: (context, state) {
        return Container(
          color: widget.showTitle
              ? Color.fromARGB((opacity * 255).round(), 255, 255, 255)
              : Color.fromARGB((opacity * 255).round(), 0, 0, 0),
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
                        ? GestureDetector(
                            onTapUp: handleTapUp,
                            child: playerWidget,
                          )
                        : GestureDetector(
                            onScaleStart: _handleOnScaleStart,
                            onScaleUpdate: _handleOnScaleUpdate,
                            onScaleEnd: _handleOnScaleEnd,
                            onHorizontalDragUpdate:
                                _scale == 1.0 ? null : handleHDragUpdate,
                            onHorizontalDragStart:
                                _scale == 1.0 ? null : handleHDragStart,
                            onHorizontalDragEnd:
                                _scale == 1.0 ? null : handleHDragEnd,
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
              Positioned(
                left: 0,
                right: 0,
                top: getDetailTop(),
                height: showDetails ? 640 : 0,
                child:
                    showDetails && _scale == 1 ? renderDetail() : Container(),
              ),
              imageData == null && playerWidget == null
                  ? Center(child: CircularProgressIndicator())
                  : Container(),
            ],
          ),
        );
      },
    );
  }
}
