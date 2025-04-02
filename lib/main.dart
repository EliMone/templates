import 'dart:async';
import 'dart:io';
import 'dart:convert'; // Needed for jsonEncode/jsonDecode
import 'package:dart_appwrite/dart_appwrite.dart'; // Use v14+ features

// This Appwrite function updates a user's labels to add 'admin'.
// Uses MODERN SDK methods (user.labels, users.updateLabels).
// *** USES context.res.send() FOR RESPONSE COMPATIBILITY ***
// Expects: {"userId": "TARGET_USER_ID", "action": "makeAdmin"}
Future<dynamic> main(final context) async {
  // --- Helper function for sending JSON responses using send() ---
  Future<dynamic> sendJsonResponse(Map<String, dynamic> data, {int statusCode = 200}) {
    final responseBody = jsonEncode(data);
    // Log just before sending
    context.log('Sending response via send() (Status $statusCode): $responseBody');
    return context.res.send(responseBody, statusCode: statusCode, headers: {'Content-Type': 'application/json'});
  }

  // --- 1. Initialize Appwrite Client ---
  final String apiKey = Platform.environment['APPWRITE_API_KEY'] ?? '';
  final String apiEndpoint = Platform.environment['APPWRITE_FUNCTION_API_ENDPOINT'] ?? '';
  final String projectId = Platform.environment['APPWRITE_FUNCTION_PROJECT_ID'] ?? '';

  if (apiKey.isEmpty || apiEndpoint.isEmpty || projectId.isEmpty) {
    context.error('Configuration Error: Missing API Key, Endpoint, or Project ID.');
    return sendJsonResponse({ // Use helper
      'success': false,
      'error': 'Function is not configured correctly.'
    }, statusCode: 500);
  }

  final client = Client()
      .setEndpoint(apiEndpoint)
      .setProject(projectId)
      .setKey(apiKey);

  final users = Users(client);

  // --- 2. Parse Request Body ---
  Map<String, dynamic> body;
  String? userId;
  String? action;
  String requestBodyRaw = context.req.bodyRaw ?? '';

  try {
    context.log('Raw request body received: $requestBodyRaw');
    if (requestBodyRaw.isEmpty) {
      context.log('Request body is empty.');
      return sendJsonResponse( // Use helper
          {'success': false, 'error': 'Request body is empty'},
          statusCode: 400);
    }

    body = jsonDecode(requestBodyRaw);
    context.log('Parsed request body: $body');

    userId = body['userId'] as String?;
    action = body['action'] as String?;

    if (userId == null || userId.isEmpty) {
      context.log('Missing or empty "userId".');
      return sendJsonResponse({ // Use helper
        'success': false,
        'error': 'Missing or empty "userId" in request body.'
      }, statusCode: 400);
    }
    if (action == null || action != 'makeAdmin') {
      context.log('Missing or invalid action. Received: $action');
      return sendJsonResponse({ // Use helper
        'success': false,
        'error': 'Missing or invalid action. Supported: "makeAdmin".'
      }, statusCode: 400);
    }

  } catch (e, stackTrace) {
    context.error('Failed to parse request body: $e\nStackTrace: $stackTrace');
    context.error('Original raw body was: $requestBodyRaw');
    return sendJsonResponse( // Use helper
        {'success': false, 'error': 'Invalid JSON format in request body.', 'details': e.toString()},
        statusCode: 400);
  }

  context.log('Attempting to add "admin" label to user (via labels): $userId');

  // --- 3. Get User, Modify Labels, Update User (Modern SDK methods) ---
  try {
    context.log('Fetching user details for $userId...');
    final user = await users.get(userId: userId); // Use modern SDK get
    context.log('Successfully fetched user details for $userId.');

    final List<String> currentLabels = List<String>.from(user.labels); // Use modern SDK labels
    context.log('Current labels: $currentLabels');

    final Set<String> newLabelsSet = Set<String>.from(currentLabels);
    bool alreadyAdmin = newLabelsSet.contains('admin');

    if (alreadyAdmin) {
      context.log('User $userId already has the "admin" label.');
      return sendJsonResponse({ // Use helper
        'success': true,
        'message': 'User already has the admin label.',
        'userId': userId,
        'labels': currentLabels,
      });
    }

    newLabelsSet.add('admin');
    final List<String> updatedLabelsList = newLabelsSet.toList();
    context.log('Prepared updated labels list: $updatedLabelsList');

    context.log('Attempting users.updateLabels for $userId...');
    await users.updateLabels(userId: userId, labels: updatedLabelsList); // Use modern SDK updateLabels
    context.log('users.updateLabels call completed successfully for $userId.');

    context.log('Successfully added "admin" label logic completed for user: $userId');
    return sendJsonResponse({ // Use helper
      'success': true,
      'message': 'Admin label added successfully.',
      'userId': userId,
      'updatedLabels': updatedLabelsList,
    });

  } on AppwriteException catch (e) {
    context.error('Appwrite Error updating labels for user $userId: [${e.code}] ${e.message} | Type: ${e.type} | Response: ${e.response}');
    int statusCode = 500;
    String errorMessage = 'Failed to update user labels due to Appwrite error.';
    if (e.code == 404) { statusCode = 404; errorMessage = 'User not found with ID: $userId'; }
    // ... other error handling ...
    final errorResponse = { 'success': false, 'error': errorMessage, 'details': e.message, 'code': e.code };
    context.log('Preparing to send Appwrite error response (Code: ${e.code})...');
    return sendJsonResponse(errorResponse, statusCode: statusCode); // Use helper

  } catch (e, stackTrace) {
    context.error('Generic unexpected error updating labels for user $userId: ${e.toString()}\nStackTrace: ${stackTrace}');
    final errorResponse = { 'success': false, 'error': 'An unexpected internal server error occurred.', 'details': e.toString() };
    context.log('Preparing to send generic error response...');
    return sendJsonResponse(errorResponse, statusCode: 500); // Use helper
  }
}
