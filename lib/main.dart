import 'dart:async';
import 'dart:io';
import 'dart:convert'; // Needed for jsonDecode (though res.json handles encoding)
import 'package:dart_appwrite/dart_appwrite.dart';

// This Appwrite function updates a user's labels to add 'admin'.
// Uses MODERN SDK methods (user.labels, users.updateLabels).
// *** USES context.res.json() FOR RESPONSE ***
// Expects: {"userId": "TARGET_USER_ID", "action": "makeAdmin"}
Future<dynamic> main(final context) async {
  // --- 1. Initialize Appwrite Client ---
  // It's generally recommended to initialize the client outside the main handler
  // if the function might be reused (warm starts), but for simplicity here is fine.
  final String apiKey = Platform.environment['APPWRITE_API_KEY'] ?? '';
  // Use the specific internal endpoint for functions
  final String apiEndpoint = Platform.environment['APPWRITE_ENDPOINT'] ?? // Use APPWRITE_ENDPOINT
                           Platform.environment['APPWRITE_FUNCTION_API_ENDPOINT'] ?? ''; // Fallback
  final String projectId = Platform.environment['APPWRITE_FUNCTION_PROJECT_ID'] ?? '';

  if (apiKey.isEmpty || apiEndpoint.isEmpty || projectId.isEmpty) {
    context.error('Configuration Error: Missing API Key, Endpoint, or Project ID.');
    // Use context.res.json directly
    return context.res.json({
      'success': false,
      'error': 'Function is not configured correctly.'
    }, statusCode: 500);
  }

  final client = Client()
      .setEndpoint(apiEndpoint) // Use the specific endpoint for functions
      .setProject(projectId)
      .setKey(apiKey)
      .setSelfSigned(status: true); // Recommended for internal communication

  final users = Users(client);

  // --- 2. Parse Request Body ---
  Map<String, dynamic> body;
  String? userId;
  String? action;
  // Use bodyRaw for potentially empty bodies, body for guaranteed non-empty string
  // bodyRaw is safer if the framework might provide null.
  String requestBodyRaw = context.req.bodyRaw ?? '';

  try {
    context.log('Raw request body received: $requestBodyRaw');
    if (requestBodyRaw.isEmpty) {
      context.log('Request body is empty.');
      // Use context.res.json directly
      return context.res.json(
          {'success': false, 'error': 'Request body is empty'},
          statusCode: 400);
    }

    body = jsonDecode(requestBodyRaw);
    context.log('Parsed request body: $body');

    // defensive casting
    userId = body['userId'] is String ? body['userId'] as String : null;
    action = body['action'] is String ? body['action'] as String : null;


    if (userId == null || userId.isEmpty) {
      context.log('Missing or empty "userId".');
      // Use context.res.json directly
      return context.res.json({
        'success': false,
        'error': 'Missing or empty "userId" in request body.'
      }, statusCode: 400);
    }
    if (action == null || action != 'makeAdmin') {
      context.log('Missing or invalid action. Received: $action');
       // Use context.res.json directly
      return context.res.json({
        'success': false,
        'error': 'Missing or invalid action. Supported: "makeAdmin".'
      }, statusCode: 400);
    }

  } catch (e, stackTrace) {
    context.error('Failed to parse request body: $e\nStackTrace: $stackTrace');
    context.error('Original raw body was: $requestBodyRaw');
     // Use context.res.json directly
    return context.res.json(
        {'success': false, 'error': 'Invalid JSON format in request body.', 'details': e.toString()},
        statusCode: 400);
  }

  context.log('Attempting to add "admin" label to user (via labels): $userId');

  // --- 3. Get User, Modify Labels, Update User (Modern SDK methods) ---
  try {
    context.log('Fetching user details for $userId...');
    final user = await users.get(userId: userId);
    context.log('Successfully fetched user details for $userId.');

    // user.labels is already List<String> in modern SDKs (check your dart_appwrite version)
    // If using an older dart_appwrite where it might be List<dynamic>, cast needed:
    // final List<String> currentLabels = List<String>.from(user.labels);
    final List<String> currentLabels = user.labels; // Assuming modern SDK
    context.log('Current labels: $currentLabels');

    final Set<String> newLabelsSet = Set<String>.from(currentLabels);
    bool alreadyAdmin = newLabelsSet.contains('admin');

    if (alreadyAdmin) {
      context.log('User $userId already has the "admin" label.');
      // Use context.res.json directly
      return context.res.json({
        'success': true,
        'message': 'User already has the admin label.',
        'userId': userId,
        'labels': currentLabels,
      }); // Default status 200 is fine
    }

    newLabelsSet.add('admin');
    final List<String> updatedLabelsList = newLabelsSet.toList();
    context.log('Prepared updated labels list: $updatedLabelsList');

    context.log('Attempting users.updateLabels for $userId...');
    await users.updateLabels(userId: userId, labels: updatedLabelsList);
    context.log('users.updateLabels call completed successfully for $userId.');

    context.log('Successfully added "admin" label logic completed for user: $userId');
    // Use context.res.json directly
    return context.res.json({
      'success': true,
      'message': 'Admin label added successfully.',
      'userId': userId,
      'updatedLabels': updatedLabelsList,
    }); // Default status 200 is fine

  } on AppwriteException catch (e) {
    context.error('Appwrite Error updating labels for user $userId: [${e.code}] ${e.message} | Type: ${e.type} | Response: ${e.response}');
    int statusCode = 500;
    String errorMessage = 'Failed to update user labels due to Appwrite error.';
    if (e.code == 404) { // User not found
        statusCode = 404;
        errorMessage = 'User not found with ID: $userId';
    } else if (e.code == 401) { // Permissions issue?
        statusCode = 401; // Or 403 Forbidden depending on context
        errorMessage = 'API Key lacks permission to update user labels.';
    } else if (e.code == 400) { // Bad request (e.g., invalid label format)
        statusCode = 400;
        errorMessage = 'Bad request updating labels.';
    }
    // Add more specific Appwrite error code handling if needed

    final errorResponse = { 'success': false, 'error': errorMessage, 'details': e.message, 'code': e.code };
    context.log('Preparing to send Appwrite error response (Code: ${e.code})...');
    // Use context.res.json directly
    return context.res.json(errorResponse, statusCode: statusCode);

  } catch (e, stackTrace) {
    context.error('Generic unexpected error updating labels for user $userId: ${e.toString()}\nStackTrace: ${stackTrace}');
    final errorResponse = { 'success': false, 'error': 'An unexpected internal server error occurred.', 'details': e.toString() };
    context.log('Preparing to send generic error response...');
    // Use context.res.json directly
    return context.res.json(errorResponse, statusCode: 500);
  }
}
