import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:document_analysis/document_analysis.dart';
import 'package:flutter/material.dart';
import 'package:mudeo/constants.dart';
import 'package:mudeo/data/models/song_model.dart';
import 'package:mudeo/utils/localization.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

class TrackScore extends StatefulWidget {
  TrackScore({this.song, this.track});

  final SongEntity song;
  final TrackEntity track;

  @override
  _TrackScoreState createState() => _TrackScoreState();
}

class _TrackScoreState extends State<TrackScore> {
  bool _isProcessing = false;
  double _distance;
  List<int> _frameTimes;
  List<String> _origPaths;
  List<String> _copyPaths;

  @override
  void initState() {
    super.initState();

    _calculateScore();
  }

  void _calculateScore() {
    final song = widget.song;
    final origTrack = song.tracks.first;
    final origData = jsonDecode(origTrack.video.recognitions);
    final copyData = jsonDecode(widget.track.video.recognitions);

    _distance = 0;
    int countParts = 0;

    if (origData == null) {
      print('## ERROR: orig is null');
      return;
    } else if (copyData == null) {
      print('## ERROR: copy is null');
      return;
    }


    int count = 0;
    for (int i = 0; i < song.duration; i += kRecognitionFrameSpeed) {
      final value = _calculateFrameScore(count);
      if (value != null) {
        _distance += value;
        countParts++;
      }
      count++;
    }

    setState(() {
      _distance = countParts > 0 ? (_distance / countParts) : 1;
    });
  }

  double _calculateFrameScore(int index) {
    final song = widget.song;
    final origTrack = song.tracks.first;
    final origData = jsonDecode(origTrack.video.recognitions);
    final copyData = jsonDecode(widget.track.video.recognitions);

    final orig = origData[index];
    final copy = copyData[index];

    int countParts = 0;

    kRecognitionParts.forEach((part) {
      final origPart = orig['$part'];
      final copyPart = copy['$part'];

      List<double> vector1 = [];
      List<double> vector2 = [];

      if (origPart != null && copyPart != null) {
        vector1.add(origPart[0]);
        vector1.add(origPart[1]);
        vector2.add(copyPart[0]);
        vector2.add(copyPart[1]);
      }

      if (vector1.isNotEmpty && vector2.isNotEmpty) {
        _distance += cosineDistance(vector1, vector2);
        countParts++;
      }
    });

    if (countParts == 0) {
      return null;
    }
    return _distance / countParts;
  }

  void _calculateDetails() async {
    setState(() {
      _isProcessing = true;
    });

    print('## _calculateDetails');
    int frameLength = kRecognitionFrameSpeed;
    _frameTimes = [];
    _origPaths = [];
    _copyPaths = [];
    final song = widget.song;
    final http.Response response =
        await http.Client().get(widget.song.tracks.first.video.url);

    final origVideoPath =
        await VideoEntity.getPath(DateTime.now().millisecondsSinceEpoch);
    await File(origVideoPath).writeAsBytes(response.bodyBytes);

    for (int i = 0; i < song.duration; i += frameLength) {
      _frameTimes.add(i);
      final path = origVideoPath.replaceFirst('.mp4', '-$i.jpg');
      await VideoThumbnail.thumbnailFile(
        video: origVideoPath,
        imageFormat: ImageFormat.JPEG,
        timeMs: i,
        thumbnailPath: path,
      );
      _origPaths.add(path);
    }

    final http.Response copyResponse =
        await http.Client().get(widget.track.video.url);

    final copyVideoPath =
        await VideoEntity.getPath(DateTime.now().millisecondsSinceEpoch);
    await File(copyVideoPath).writeAsBytes(copyResponse.bodyBytes);

    for (int i = 0; i < song.duration; i += frameLength) {
      final copyPath = copyVideoPath.replaceFirst('.mp4', '-$i.jpg');
      await VideoThumbnail.thumbnailFile(
        video: copyVideoPath,
        imageFormat: ImageFormat.JPEG,
        timeMs: i,
        thumbnailPath: copyPath,
      );
      _copyPaths.add(copyPath);
    }

    setState(() {
      _isProcessing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final localization = AppLocalization.of(context);
    final song = widget.song;
    final origTrack = song.tracks.first;
    final origData = jsonDecode(origTrack.video.recognitions);
    final copyData = jsonDecode(widget.track.video.recognitions);
    print('## origData: $origData');

    return AlertDialog(
        contentPadding: const EdgeInsets.all(16),
        actions: <Widget>[
          if (_frameTimes == null)
            FlatButton(
              child: Text(localization.showDetails.toUpperCase()),
              onPressed: () {
                _calculateDetails();
              },
            ),
          FlatButton(
            child: Text(localization.close.toUpperCase()),
            onPressed: () {
              Navigator.of(context).pop();
            },
          )
        ],
        content: SingleChildScrollView(
          child: Column(
            children: <Widget>[
              if (_distance != null) ...[
                Padding(
                  padding: const EdgeInsets.all(15),
                  child: Text('Your score is:'),
                ),
                SizedBox(height: 10),
                Text(
                  '${(100 - (_distance * 100)).round()}%',
                  style: Theme.of(context).textTheme.headline4,
                ),
                SizedBox(height: 20),
              ],
              if (_isProcessing)
                LinearProgressIndicator()
              else if (_frameTimes != null)
                for (int i = 0; i < _frameTimes.length; i++)
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Stack(
                          children: <Widget>[
                            Image.file(File(_origPaths[
                                _frameTimes.indexOf(_frameTimes[i])])),
                            Text(origData[i].toString()),
                          ],
                        ),
                      ),
                      Expanded(
                          child: Stack(
                        children: <Widget>[
                          Image.file(File(
                              _copyPaths[_frameTimes.indexOf(_frameTimes[i])])),
                          Text(copyData[i].toString()),
                        ],
                      )),
                    ],
                  ),
            ],
          ),
        ));
  }
}