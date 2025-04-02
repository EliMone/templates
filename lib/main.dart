import 'dart:async';
import 'dart:io';
import 'dart:convert'; // Needed for jsonEncode
import 'package:dart_appwrite/dart_appwrite.dart';

// Uses context.res.send() FOR ALL RESPONSES - TESTING STEP 3
Future<dynamic> main(final context) async {
  // --- Initialize Client ---
  final String apiKey = Platform.environment['APPWRITE_API_KEY'] ?? '';
  final String apiEndpoint = Platform.environment['APPWRITE_ENDPOINT'] ?? '';
  final String projectId = Platform.environment['APPWRITE_FUNCTION_PROJECT_ID'] ?? '';

  final Map<String, String> jsonHeaders = {
    'Content-Type': 'application/json; charset=utf-8'
  };

  if (apiKey.isEmpty || apiEndpoint.isEmpty || projectId.isEmpty) {
    context.error('Configuration Error: Missing API Key, Endpoint, or Project ID.');
    final responseData = {
      'success': false,
      'error': 'Function is not configured correctly.'
    };
    final responseBody = jsonEncode(responseData);
    context.log('Attempting response via send() [Config Error]: $responseBody');
    return context.res.send(responseBody, statusCode: 500, headers: jsonHeaders);
  }

  final client = Client()
      .setEndpoint(apiEndpoint)
      .setProject(projectId)
      .setKey(apiKey)
      .setSelfSigned(status: true); // Keep if needed for self-hosting

  final users = Users(client);

  // --- Parse Request Body ---
  Map<String, dynamic> body;
  String? userId;
  String? action;
  String requestBodyRaw = context.req.bodyRaw ?? '';

  try {
    context.log('Raw request body received: $requestBodyRaw');
    if (requestBodyRaw.isEmpty) {
      context.log('Request body is empty.');
      final responseData = {'success': false, 'error': 'Request body is empty'};
      final responseBody = jsonEncode(responseData);
      context.log('Attempting response via send() [Empty Body]: $responseBody');
      return context.res.send(responseBody, statusCode: 400, headers: jsonHeaders);
    }
    body = jsonDecode(requestBodyRaw);
    context.log('Parsed request body: $body');

    userId = body['userId'] as String?; // Add safety checks if needed
    action = body['action'] as String?;

    if (userId == null || userId.isEmpty) {
      context.log('Missing or empty "userId".');
      final responseData = {'success': false, 'error': 'Missing or empty "userId"'};
      final responseBody = jsonEncode(responseData);
      context.log('Attempting response via send() [Missing UserID]: $responseBody');
      return context.res.send(responseBody, statusCode: 400, headers: jsonHeaders);
    }
    if (action == null || action != 'makeAdmin') {
      context.log('Missing or invalid action. Received: $action');
      final responseData = {'success': false, 'error': 'Missing or invalid action. Supported: "makeAdmin"'};
      final responseBody = jsonEncode(responseData);
      context.log('Attempting response via send() [Invalid Action]: $responseBody');
      return context.res.send(responseBody, statusCode: 400, headers: jsonHeaders);
    }

  } catch (e, stackTrace) {
    context.error('Failed to parse request body: $e\nStackTrace: $stackTrace');
    final responseData = {'success': false, 'error': 'Invalid JSON format.', 'details': e.toString()};
    final responseBody = jsonEncode(responseData);
    context.log('Attempting response via send() [JSON Parse Error]: $responseBody');
    return context.res.send(responseBody, statusCode: 400, headers: jsonHeaders);
  }

  // --- Update User Labels ---
  try {
    context.log('Fetching user details for $userId...');
    final user = await users.get(userId: userId);
    context.log('Successfully fetched user details for $userId.');

    final List<String> currentLabels = user.labels; // Assuming modern SDK
    context.log('Current labels: $currentLabels');

    final Set<String> newLabelsSet = Set<String>.from(currentLabels);
    bool alreadyAdmin = newLabelsSet.contains('admin');

    if (alreadyAdmin) {
      context.log('User $userId already has the "admin" label.');
      final responseData = {
        'success': true,
        'message': 'User already has the admin label.',
        'userId': userId,
        'labels': currentLabels,
      };
      final responseBody = jsonEncode(responseData);
      context.log('Attempting response via send() [Already Admin]: $responseBody');
      return context.res.send(responseBody, statusCode: 200, headers: jsonHeaders); // Use 200 OK
    }

    newLabelsSet.add('admin');
    final List<String> updatedLabelsList = newLabelsSet.toList();
    context.log('Prepared updated labels list: $updatedLabelsList');

    context.log('Attempting users.updateLabels for $userId...');
    await users.updateLabels(userId: userId, labels: updatedLabelsList);
    context.log('users.updateLabels call completed successfully for $userId.');

    final responseData = {
        'success': true,
        'message': 'Admin label added successfully.',
        'userId': userId,
        'updatedLabels': updatedLabelsList,
    };
    final responseBody = jsonEncode(responseData);
    context.log('Attempting response via send() [Success]: $responseBody');
    return context.res.send(responseBody, statusCode: 200, headers: jsonHeaders); // Use 200 OK

  } on AppwriteException catch (e) {
    context.error('Appwrite Error updating labels for user $userId: [${e.code}] ${e.message} | Type: ${e.type} | Response: ${e.response}');

    int statusCode = 500;
    String errorMessage = 'Failed to update user labels due to Appwrite error.';

    if (e.code == 404) { statusCode = 404; errorMessage = 'User not found with ID: $userId'; }
    else if (e.code == 401) { statusCode = 401; errorMessage = 'API Key lacks permission to update user labels.'; }
    else if (e.code == 400) { statusCode = 400; errorMessage = 'Bad request updating labels (check label format/content).'; }

    final responseData = {
        'success': false,
        'error': errorMessage,
        'details': e.message,
        'code': e.code
    };
    final responseBody = jsonEncode(responseData);
    context.log('Attempting response via send() [Appwrite Error]: $responseBody');
    return context.res.send(responseBody, statusCode: statusCode, headers: jsonHeaders);

  } catch (e, stackTrace) {
    context.error('Generic unexpected error updating labels for user $userId: ${e.toString()}\nStackTrace: ${stackTrace}');
    final responseData = {
      'success': false,
      'error': 'An unexpected internal server error occurred.',
      'details': e.toString()
    };
    final responseBody = jsonEncode(responseData);
    context.log('Attempting response via send() [Generic Error]: $responseBody');
    return context.res.send(responseBody, statusCode: 500, headers: jsonHeaders);
  }
}
