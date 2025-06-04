import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:youtube_api_client/model/youtube_api_result.dart';
import 'package:youtube_api_client/video.dart';
import 'package:youtube_api_client/playlist.dart';
import 'package:youtube_api_client/channel.dart';
import 'package:youtube_api_client/search.dart';

export 'package:youtube_api_client/model/youtube_api_result.dart';
export 'package:youtube_api_client/video.dart';
export 'package:youtube_api_client/playlist.dart';
export 'package:youtube_api_client/channel.dart';
export 'package:youtube_api_client/search.dart';
export 'package:youtube_api_client/model/thumbnails/thumbnail_resolution.dart';

class YoutubeApi {
  late SearchOptions searchOptions;
  String key;
  String? nextPageToken;
  String? prevPageToken;
  static const baseURL = 'www.googleapis.com';
  static const searchUnencodedPath = "youtube/v3/search";
  static const playlistItemsUnencodedPath = "youtube/v3/playlistItems";
  int page = 0;
  final headers = {"Accept": "application/json"};
  YoutubeApi(
    this.key, {
    int maxResults = 10,
  }) {
    searchOptions = SearchOptions(maxResults: maxResults);
  }

  Future<List<ApiResult>> getTrends(
      {required String regionCode,
      Set<VideoPart> parts = const {VideoPart.snippet}}) async {
    final url = _getTrendingVideosUri(regionCode: regionCode, parts: parts);
    final res = await http.get(url, headers: headers);
    final jsonData = json.decode(res.body);
    if (jsonData['error'] != null) {
      throw jsonData['error']['message'];
    }
    if (jsonData['pageInfo']['totalResults'] == null) return <ApiResult>[];
    return _getResultsFromJson(jsonData, isSpecificKind: true, newPage: 1);
  }

  Future<List<ApiResult>> search(
    String query, {
    SearchOptions options = const SearchOptions(
      type: ResultType.values,
      order: Order.relevance,
      videoDuration: VideoDuration.any,
    ),
  }) async {
    searchOptions = options.copyWith(query: query);
    final url = _getSearchUri(options: searchOptions);
    var res = await http.get(url, headers: headers);
    var jsonData = json.decode(res.body);
    return _getResultsFromJson(jsonData, newPage: 1);
  }

  Future<List<ApiResult>> channel(String channelId, {Order? order}) async {
    final url = _getSearchInChannelUri(channelId, order);
    var res = await http.get(url, headers: headers);
    var jsonData = json.decode(res.body);
    if (jsonData['error'] != null) {
      throw jsonData['error']['message'];
    }
    if (jsonData['pageInfo']['totalResults'] == null) return <ApiResult>[];
    return _getResultsFromJson(jsonData, newPage: 1);
  }

  /// Get video results by ID
  Future<List<YoutubeVideo>> searchVideosById(List<String> ids,
      {Set<VideoPart> parts = VideoPart.implementedParts}) async {
    final url = _getVideoUri(ids, parts: parts);
    var res = await http.get(url, headers: headers);
    var jsonData = json.decode(res.body);
    final result = List.castFrom<ApiResult, YoutubeVideo>(
        await _getResultsFromJson(jsonData, isSpecificKind: true, newPage: 1));
    return result;
  }

  /// Get channel results by ID
  Future<List<YoutubeChannel>> searchChannelsById(List<String> ids,
      {Set<ChannelPart> parts = ChannelPart.implementedParts}) async {
    final url = _getChannelUri(ids, parts: parts);
    var res = await http.get(url, headers: headers);
    var jsonData = json.decode(res.body) as Map<String, dynamic>;
    final result = List.castFrom<ApiResult, YoutubeChannel>(
        await _getResultsFromJson(jsonData, isSpecificKind: true, newPage: 1));
    return result;
  }

  /// Get channel results by ID
  Future<List<YoutubePlaylist>> searchPlaylistsById(List<String> ids,
      {Set<PlaylistPart> parts = PlaylistPart.implementedParts}) async {
    final url = _getPlaylistUri(ids, parts: parts);
    var res = await http.get(url, headers: headers);
    var jsonData = json.decode(res.body) as Map<String, dynamic>;
    final result = List.castFrom<ApiResult, YoutubePlaylist>(
        await _getResultsFromJson(jsonData, isSpecificKind: true, newPage: 1));
    return result;
  }

  /// Get videos from a playlist by playlist ID
  Future<List<YoutubeVideo>> getVideosByPlaylistId(String playlistId,
      {int maxResults = 50}) async {
    final url = _getPlaylistItemsUri(playlistId, maxResults: maxResults);
    var res = await http.get(url, headers: headers);
    var jsonData = json.decode(res.body) as Map<String, dynamic>;

    if (jsonData['error'] != null) {
      throw jsonData['error']['message'];
    }

    if (jsonData['pageInfo']['totalResults'] == null) return <YoutubeVideo>[];

    // Store pagination tokens
    nextPageToken = jsonData['nextPageToken'];
    prevPageToken = jsonData['prevPageToken'];

    final items = jsonData['items'] as List;
    final result = <YoutubeVideo>[];

    // Extract video IDs from playlist items
    final videoIds = <String>[];
    for (final item in items) {
      final videoId = item['snippet']['resourceId']['videoId'] as String?;
      if (videoId != null) {
        videoIds.add(videoId);
      }
    }

    // Fetch full video details if we have video IDs
    if (videoIds.isNotEmpty) {
      return await searchVideosById(videoIds);
    }

    return result;
  }

  Future<List<ApiResult>> _getResultsFromJson(Map<String, dynamic>? data,
      {bool isSpecificKind = false, int? newPage}) async {
    if (data == null) return <ApiResult>[];

    if (data['error'] != null) {
      throw data['error']['message'];
    }
    if (newPage != null) page = newPage;
    if (data['pageInfo']['totalResults'] == null) return [];

    nextPageToken = data['nextPageToken'];
    prevPageToken = data['prevPageToken'];
    int total =
        data['pageInfo']['totalResults'] < data['pageInfo']['resultsPerPage']
            ? data['pageInfo']['totalResults']
            : data['pageInfo']['resultsPerPage'];

    final result = <ApiResult>[];
    for (int i = 0; i < total; i++) {
      ApiResult ytApiObj =
          ApiResult.fromMap(data['items'][i], isSpecificKind: isSpecificKind);
      result.add(ytApiObj);
    }
    return result;
  }

  Future<List<ApiResult>?> prevPage({bool isTrendingVideos = false}) async {
    if (prevPageToken == null) return null;
    final url = _getPrevPageUri(onlyVideos: isTrendingVideos);
    var res = await http.get(url, headers: headers);
    var jsonData = json.decode(res.body);

    return _getResultsFromJson(jsonData,
        isSpecificKind: isTrendingVideos, newPage: page - 1);
  }

  Future<List<ApiResult>?> nextPage({bool isTrendingVideos = false}) async {
    if (nextPageToken == null) return null;
    final url = _getNextPageUri(onlyVideos: isTrendingVideos);
    var res = await http.get(url, headers: headers);
    var jsonData = json.decode(res.body);
    return _getResultsFromJson(jsonData,
        isSpecificKind: isTrendingVideos, newPage: page + 1);
  }

  /// Get next page of videos from a playlist
  Future<List<YoutubeVideo>?> nextPlaylistPage(String playlistId) async {
    if (nextPageToken == null) return null;
    final url = _getPlaylistItemsUri(playlistId, pageToken: nextPageToken);
    var res = await http.get(url, headers: headers);
    var jsonData = json.decode(res.body) as Map<String, dynamic>;

    if (jsonData['error'] != null) {
      throw jsonData['error']['message'];
    }

    if (jsonData['pageInfo']['totalResults'] == null) return <YoutubeVideo>[];

    // Store pagination tokens
    nextPageToken = jsonData['nextPageToken'];
    prevPageToken = jsonData['prevPageToken'];
    page = page + 1;

    final items = jsonData['items'] as List;

    // Extract video IDs from playlist items
    final videoIds = <String>[];
    for (final item in items) {
      final videoId = item['snippet']['resourceId']['videoId'] as String?;
      if (videoId != null) {
        videoIds.add(videoId);
      }
    }

    // Fetch full video details if we have video IDs
    if (videoIds.isNotEmpty) {
      return await searchVideosById(videoIds);
    }

    return <YoutubeVideo>[];
  }

  /// Get previous page of videos from a playlist
  Future<List<YoutubeVideo>?> prevPlaylistPage(String playlistId) async {
    if (prevPageToken == null) return null;
    final url = _getPlaylistItemsUri(playlistId, pageToken: prevPageToken);
    var res = await http.get(url, headers: headers);
    var jsonData = json.decode(res.body) as Map<String, dynamic>;

    if (jsonData['error'] != null) {
      throw jsonData['error']['message'];
    }

    if (jsonData['pageInfo']['totalResults'] == null) return <YoutubeVideo>[];

    // Store pagination tokens
    nextPageToken = jsonData['nextPageToken'];
    prevPageToken = jsonData['prevPageToken'];
    page = page - 1;

    final items = jsonData['items'] as List;

    // Extract video IDs from playlist items
    final videoIds = <String>[];
    for (final item in items) {
      final videoId = item['snippet']['resourceId']['videoId'] as String?;
      if (videoId != null) {
        videoIds.add(videoId);
      }
    }

    // Fetch full video details if we have video IDs
    if (videoIds.isNotEmpty) {
      return await searchVideosById(videoIds);
    }

    return <YoutubeVideo>[];
  }

  int get getPage => page;

  Uri _getTrendingVideosUri(
      {required String regionCode,
      Set<VideoPart> parts = const {VideoPart.snippet}}) {
    final options = _getTrendingOption(regionCode, parts: parts).getMap(key);
    Uri url = Uri.https(baseURL, ResultType.video.unencodedPath, options);
    return url;
  }

  Uri _getVideoUri(List<String> videoIds, {Set<VideoPart>? parts}) {
    final videoOptions = VideoOptions(
      parts: parts ?? const {VideoPart.snippet},
      id: videoIds,
      maxResults: videoIds.length,
    );
    Uri url = Uri.https(
        baseURL, ResultType.video.unencodedPath, videoOptions.getMap(key));
    return url;
  }

  Uri _getChannelUri(List<String> channelIds, {Set<ChannelPart>? parts}) {
    final channelOptions = ChannelOptions(
      parts: parts ?? const {ChannelPart.snippet},
      id: channelIds,
      maxResults: channelIds.length,
    );
    Uri url = Uri.https(
        baseURL, ResultType.channel.unencodedPath, channelOptions.getMap(key));
    return url;
  }

  Uri _getPlaylistUri(List<String> playlistIds, {Set<PlaylistPart>? parts}) {
    final playlistOptions = PlaylistOptions(
      parts: parts ?? const {PlaylistPart.snippet},
      id: playlistIds,
      maxResults: playlistIds.length,
    );
    Uri url = Uri.https(baseURL, ResultType.playlist.unencodedPath,
        playlistOptions.getMap(key));
    return url;
  }

  Uri _getPlaylistItemsUri(String playlistId,
      {int maxResults = 50, String? pageToken}) {
    final params = {
      'key': key,
      'playlistId': playlistId,
      'part': 'snippet',
      'maxResults': maxResults.toString(),
      if (pageToken != null) 'pageToken': pageToken,
    };
    return Uri.https(baseURL, playlistItemsUnencodedPath, params);
  }

  Uri _getSearchInChannelUri(String channelId, Order? order) {
    searchOptions = SearchOptions(
      channelId: channelId,
      order: order ?? Order.date,
      maxResults: searchOptions.maxResults,
    );
    return Uri.https(baseURL, searchUnencodedPath, searchOptions.getMap(key));
  }

  Uri _getSearchUri({required SearchOptions options}) =>
      Uri.https(baseURL, searchUnencodedPath, options.getMap(key));

  ///  For Getting Getting Previous Page
  Uri _getPrevPageUri({bool onlyVideos = false}) {
    Uri url;
    if (onlyVideos) {
      final videoOptions = _getTrendingPageOption(prevPageToken!);
      url = Uri.https(
          baseURL, ResultType.video.unencodedPath, videoOptions.getMap(key));
    } else {
      searchOptions = SearchOptions(
        query: searchOptions.query,
        pageToken: prevPageToken!,
        channelId: searchOptions.channelId,
        maxResults: searchOptions.maxResults,
      );
      url = Uri.https(baseURL, searchUnencodedPath, searchOptions.getMap(key));
    }
    return url;
  }

  ///  For Getting Getting Next Page
  Uri _getNextPageUri({bool onlyVideos = false}) {
    Uri url;
    if (onlyVideos) {
      final videoOptions = _getTrendingPageOption(nextPageToken!);
      url = Uri.https(
          baseURL, ResultType.video.unencodedPath, videoOptions.getMap(key));
    } else {
      searchOptions = SearchOptions(
        query: searchOptions.query,
        pageToken: nextPageToken!,
        channelId: searchOptions.channelId,
        maxResults: searchOptions.maxResults,
      );
      url = Uri.https(baseURL, searchUnencodedPath, searchOptions.getMap(key));
    }
    return url;
  }

  VideoOptions _getTrendingOption(String regionCode,
          {Set<VideoPart> parts = const {VideoPart.snippet}}) =>
      VideoOptions(
        parts: parts,
        chart: Chart.mostPopular,
        maxResults: searchOptions.maxResults,
        regionCode: regionCode,
      );

  VideoOptions _getTrendingPageOption(String token) => VideoOptions(
        chart: Chart.mostPopular,
        maxResults: searchOptions.maxResults,
        regionCode: searchOptions.regionCode,
        pageToken: token,
      );
}
