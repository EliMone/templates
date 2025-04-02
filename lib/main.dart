import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:dart_appwrite/dart_appwrite.dart'; // Will use v14+ now

// This Appwrite function updates a user's labels to add 'admin'.
// Uses MODERN SDK methods (user.labels, users.updateLabels, context.res.json).
// Expects: {"userId": "TARGET_USER_ID", "action": "makeAdmin"}
Future<dynamic> main(final context) async {
  // --- 1. Initialize Appwrite Client ---
  final String apiKey = Platform.environment['APPWRITE_API_KEY'] ?? '';
  final String apiEndpoint = Platform.environment['APPWRITE_FUNCTION_API_ENDPOINT'] ?? '';
  final String projectId = Platform.environment['APPWRITE_FUNCTION_PROJECT_ID'] ?? '';

  if (apiKey.isEmpty || apiEndpoint.isEmpty || projectId.isEmpty) {
    context.error('Configuration Error: Missing API Key, Endpoint, or Project ID.');
    // Use context.res.json as the runtime should now support it
    return context.res.json({
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
      return context.res.json(
          {'success': false, 'error': 'Request body is empty'},
          statusCode: 400);
    }

    body = jsonDecode(requestBodyRaw);
    context.log('Parsed request body: $body');

    userId = body['userId'] as String?;
    action = body['action'] as String?;

    if (userId == null || userId.isEmpty) {
      context.log('Missing or empty "userId".');
      return context.res.json({
        'success': false,
        'error': 'Missing or empty "userId" in request body.'
      }, statusCode: 400);
    }
    if (action == null || action != 'makeAdmin') {
      context.log('Missing or invalid action. Received: $action');
      return context.res.json({
        'success': false,
        'error': 'Missing or invalid action. Supported: "makeAdmin".'
      }, statusCode: 400);
    }

  } catch (e, stackTrace) {
    context.error('Failed to parse request body: $e\nStackTrace: $stackTrace');
    context.error('Original raw body was: $requestBodyRaw');
    return context.res.json(
        {'success': false, 'error': 'Invalid JSON format in request body.', 'details': e.toString()},
        statusCode: 400);
  }

  context.log('Attempting to add "admin" label to user (via labels): $userId');

  // --- 3. Get User, Modify Labels, Update User ---
  try {
    context.log('Fetching user details for $userId...');
    // Use users.get() which returns a User model in v14+
    final user = await users.get(userId: userId);
    context.log('Successfully fetched user details for $userId.');

    // Access labels directly from the user object (available in v14+)
    final List<String> currentLabels = List<String>.from(user.labels);
    context.log('Current labels: $currentLabels');


    final Set<String> newLabelsSet = Set<String>.from(currentLabels);
    bool alreadyAdmin = newLabelsSet.contains('admin');

    if (alreadyAdmin) {
      context.log('User $userId already has the "admin" label.');
      return context.res.json({
        'success': true,
        'message': 'User already has the admin label.',
        'userId': userId,
        'labels': currentLabels,
      });
    }

    newLabelsSet.add('admin');
    final List<String> updatedLabelsList = newLabelsSet.toList();
    context.log('Prepared updated labels list: $updatedLabelsList');

    // --- CRITICAL STEP (Using updateLabels) ---
    context.log('Attempting users.updateLabels for $userId...');
    // Use users.updateLabels (available in v14+)
    await users.updateLabels(userId: userId, labels: updatedLabelsList);
    context.log('users.updateLabels call completed successfully for $userId.');
    // --- END CRITICAL STEP ---

    context.log('Successfully added "admin" label logic completed for user: $userId');
    return context.res.json({
      'success': true,
      'message': 'Admin label added successfully.',
      'userId': userId,
      'updatedLabels': updatedLabelsList,
    });

  } on AppwriteException catch (e) {
    context.error(
        'Appwrite Error updating labels for user $userId: [${e.code}] ${e.message} | Type: ${e.type} | Response: ${e.response}');
    int statusCode = 500;
    String errorMessage = 'Failed to update user labels due to Appwrite error.';
      if (e.code == 404) { statusCode = 404; errorMessage = 'User not found with ID: $userId'; }
      // Add other specific error code handling if needed (400, 401, 409, etc.)
    final errorResponse = { 'success': false, 'error': errorMessage, 'details': e.message, 'code': e.code };
    context.log('Preparing to send Appwrite error response (Code: ${e.code})...');
    return context.res.json(errorResponse, statusCode: statusCode);

  } catch (e, stackTrace) {
    context.error('Generic unexpected error updating labels for user $userId: ${e.toString()}\nStackTrace: ${stackTrace}');
    final errorResponse = { 'success': false, 'error': 'An unexpected internal server error occurred.', 'details': e.toString() };
    context.log('Preparing to send generic error response...');
    return context.res.json(errorResponse, statusCode: 500);
  }
}
