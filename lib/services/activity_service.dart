import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../core/api_client.dart';
import '../models/activity.dart';

class ActivityService {
  // Get all activities - GET /activities
  Future<List<Activity>> getActivities() async {
    final res = await ApiClient.get('/activities');

    debugPrint('API RESPONSE [/activities]: ${res.statusCode} - ${res.body}');

    if (res.statusCode != 200) {
      throw Exception('Error getting activities: ${res.statusCode}');
    }

    final List data = jsonDecode(utf8.decode(res.bodyBytes));
    return data.map((json) => Activity.fromJson(json)).toList();
  }

  // Get an activity by id - GET /activities/{id}
  Future<Activity> getActivity(int id) async {
    final res = await ApiClient.get('/activities/$id');

    if (res.statusCode != 200) {
      throw Exception('Error getting activity: ${res.statusCode}');
    }

    return Activity.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  // Create an activity - POST /activities
  Future<Activity> createActivity(Activity activity) async {
    final res = await ApiClient.post(
      '/activities',
      body: activity.toJson(),
    );

    if (res.statusCode != 201) {
      throw Exception('Error creating activity: ${res.statusCode}');
    }

    return Activity.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  // Update an activity - PUT /activities/{id}
  Future<Activity> updateActivity(int id, Activity activity) async {
    final res = await ApiClient.put(
      '/activities/$id',
      body: activity.toJson(),
    );

    if (res.statusCode != 200) {
      throw Exception('Error updating activity: ${res.statusCode}');
    }

    return Activity.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  // Delete an activity - DELETE /activities/{id}
  Future<void> deleteActivity(int id) async {
    final res = await ApiClient.delete('/activities/$id');

    if (res.statusCode != 204) {
      throw Exception('Error deleting activity: ${res.statusCode}');
    }
  }
}