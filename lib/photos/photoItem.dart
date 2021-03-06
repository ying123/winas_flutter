import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';

import '../redux/redux.dart';
import '../common/cache.dart';
import '../common/taskManager.dart';
import '../common/placeHolderImage.dart';

class PhotoItem extends StatefulWidget {
  PhotoItem({Key key, this.item, this.showPhoto, this.cellSize, this.select})
      : super(key: key);
  final Entry item;
  final Function showPhoto;
  final double cellSize;
  final Select select;
  @override
  _PhotoItemState createState() => _PhotoItemState();
}

class _PhotoItemState extends State<PhotoItem> {
  Uint8List thumbData;
  ThumbTask task;

  Future<void> _getThumb(AppState state) async {
    // check hash
    if (widget.item.hash == null) return;

    // try get cached file
    final cm = await CacheManager.getInstance();
    final data = await cm.getCachedThumbData(widget.item);
    if (data != null && this.mounted) {
      setState(() {
        thumbData = data;
        _image = Image.memory(
          thumbData,
          fit: BoxFit.cover,
        );
      });
      return;
    } else {
      thumbData = null;
    }

    // download thumb via queue
    final tm = TaskManager.getInstance();
    TaskProps props = TaskProps(entry: widget.item, state: state);
    task = tm.createThumbTask(props, (error, value) {
      if (error == null && value is Uint8List && this.mounted) {
        setState(() {
          thumbData = value;
          _image = Image.memory(
            thumbData,
            fit: BoxFit.cover,
          );
        });
      } else {
        thumbData = null;
      }
      task = null;
    });
  }

  _onTap(BuildContext ctx) {
    if (widget.select.selectMode()) {
      widget.select.toggleSelect(widget.item);
    } else {
      widget.showPhoto(ctx, widget.item, thumbData);
    }
  }

  Image _image = Image.memory(
    placeHolderImage,
    fit: BoxFit.cover,
  );

  @override
  void dispose() {
    task?.abort();
    task = null;
    thumbData = null;
    _image.image.evict().catchError(print);
    _image = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.item;
    return StoreConnector<AppState, AppState>(
      onInit: (store) => _getThumb(store.state),
      onDispose: (store) => {},
      converter: (store) => store.state,
      builder: (ctx, state) {
        return Container(
          child: Material(
            child: InkWell(
              onTap: () => _onTap(ctx),
              onLongPress: () => widget.select.toggleSelect(entry),
              child: Stack(
                children: <Widget>[
                  // thumbnails
                  Positioned.fill(
                    child: _image,
                  ),
                  // video duration
                  Positioned(
                    height: 24,
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: widget.item.metadata.duration == null
                        ? Container()
                        : Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Colors.black26],
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: <Widget>[
                                Text(
                                  widget.item.metadata.duration,
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w500),
                                ),
                                Container(width: 6),
                              ],
                            ),
                          ),
                  ),
                  Positioned.fill(
                    child: entry.selected
                        ? Container(
                            color: Colors.black12,
                            child: Center(
                              child: Container(
                                height: 48,
                                width: 48,
                                child: entry.selected
                                    ? Icon(Icons.check, color: Colors.white)
                                    : Container(),
                                decoration: BoxDecoration(
                                  color: entry.selected
                                      ? Colors.teal
                                      : Colors.black12,
                                  borderRadius: BorderRadius.all(
                                    Radius.circular(24),
                                  ),
                                ),
                              ),
                            ),
                          )
                        : Container(),
                  )
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
