import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:share_extend/share_extend.dart';
import 'package:flutter_redux/flutter_redux.dart';

import './gridPhoto.dart';
import './gridVideo.dart';
import '../redux/redux.dart';
import '../common/utils.dart';
import '../common/cache.dart';
import '../files/delete.dart';
import '../transfer/manager.dart';

const videoTypes = 'RM.RMVB.WMV.AVI.MP4.3GP.MKV.MOV.FLV.MPEG';
List<String> photoMagic = ['JPEG', 'GIF', 'PNG', 'BMP'];

class PageViewer extends StatefulWidget {
  const PageViewer(
      {Key key, this.photo, this.thumbData, this.list, this.updateList})
      : super(key: key);
  final Uint8List thumbData;
  final List list;
  final Entry photo;
  final Function updateList;
  @override
  _PageViewerState createState() => _PageViewerState();
}

class _PageViewerState extends State<PageViewer> {
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

  @override
  void dispose() {
    currentItem = null;
    myScrollController?.dispose();
    pageController?.dispose();
    super.dispose();
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
      showTitle = show;
    } else {
      showTitle = !showTitle;
    }

    // // show/hidden status bar
    // if (showTitle) {
    //   SystemChrome.setEnabledSystemUIOverlays(SystemUiOverlay.values);
    // } else {
    //   SystemChrome.setEnabledSystemUIOverlays([SystemUiOverlay.bottom]);
    // }

    setState(() {});
  }

  void _share(BuildContext ctx, Entry entry, AppState state) async {
    final dialog = DownloadingDialog(ctx, entry.size);
    dialog.openDialog();

    final cm = await CacheManager.getInstance();
    String entryPath = await cm.getPhotoPathWithTrueName(entry, state,
        onProgress: dialog.onProgress, cancelToken: dialog.cancelToken);

    dialog.close();
    if (dialog.canceled) {
      showSnackBar(ctx, i18n('Download Canceled'));
    } else if (entryPath == null) {
      showSnackBar(ctx, i18n('Download Failed'));
    } else {
      try {
        final type =
            photoMagic.indexOf(entry?.metadata?.type) > -1 ? 'image' : 'file';
        ShareExtend.share(entryPath, type);
      } catch (error) {
        debug(error);
        showSnackBar(ctx, i18n('No Available App to Open This File'));
      }
    }
  }

  void _download(BuildContext ctx, Entry entry, AppState state) async {
    final cm = TransferManager.getInstance();
    cm.newDownload(entry, state);
    showSnackBar(ctx, i18n('File Add to Transfer List'));
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
      showSnackBar(ctx, i18n('Delete Success'));
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
      showSnackBar(ctx, i18n('Delete Failed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: StoreConnector<AppState, AppState>(
        converter: (store) => store.state,
        builder: (context, state) {
          return Stack(
            children: <Widget>[
              Positioned.fill(
                child: PageView.builder(
                  controller: pageController,
                  itemBuilder: (context, position) {
                    final Entry item = widget.list[position];
                    final ext = item?.metadata?.type?.toUpperCase();
                    final isVideo = videoTypes.split('.').contains(ext);
                    final view = isVideo
                        ? GridVideo(
                            updateOpacity: updateOpacity,
                            video: item,
                            thumbData:
                                item == widget.photo ? widget.thumbData : null,
                            toggleTitle: toggleTitle,
                            showTitle: showTitle,
                          )
                        : GridPhoto(
                            updateOpacity: updateOpacity,
                            photo: item,
                            thumbData:
                                item == widget.photo ? widget.thumbData : null,
                            toggleTitle: toggleTitle,
                            showTitle: showTitle,
                          );
                    return Container(child: view);
                  },
                  itemCount: widget.list.length,
                  onPageChanged: (int index) {
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
                left: 0,
                right: 0,
                top: 0,
                // use `MediaQuery.of(context).padding.top` to fix bug in screens withs notch
                // see AppBar and SafeArea
                child: showTitle
                    ? Material(
                        elevation: 1.0,
                        color: Colors.white,
                        child: Padding(
                          padding: EdgeInsets.only(
                            top: MediaQuery.of(context).padding.top,
                          ),
                          child: MediaQuery.removePadding(
                            context: context,
                            removeTop: true,
                            child: AppBar(
                              primary: false,
                              automaticallyImplyLeading: false,
                              brightness: Brightness.light,
                              backgroundColor: Colors.white,
                              elevation: 0.0,
                              leading: IconButton(
                                icon: Icon(Icons.close, color: Colors.black38),
                                onPressed: () => Navigator.pop(context),
                              ),
                              actions: <Widget>[
                                // share
                                IconButton(
                                  icon:
                                      Icon(Icons.share, color: Colors.black38),
                                  onPressed: () =>
                                      _share(context, currentItem, state),
                                ),
                                // download
                                IconButton(
                                  icon: Icon(Icons.file_download),
                                  color: Colors.black38,
                                  onPressed: () =>
                                      _download(context, currentItem, state),
                                ),
                                // delete
                                IconButton(
                                  icon: Icon(Icons.delete),
                                  color: Colors.black38,
                                  onPressed: () =>
                                      _delete(context, currentItem, state),
                                ),
                              ],
                            ),
                          ),
                        ))
                    : Container(),
              ),
            ],
          );
        },
      ),
    );
  }
}
