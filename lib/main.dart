import 'dart:async';
import 'dart:io';
import 'dart:convert'; // Needed for jsonEncode/jsonDecode
import 'package:dart_appwrite/dart_appwrite.dart';

// This Appwrite function updates a user's labels to add 'admin'.
// Uses SDK v8.0.0 compatible methods (getPrefs/updatePrefs).
// Uses context.res.send() for compatibility with older runtimes.
// Expects: {"userId": "TARGET_USER_ID", "action": "makeAdmin"}
Future<dynamic> main(final context) async {
  // --- Helper function for sending JSON responses ---
  Future<dynamic> sendJsonResponse(Map<String, dynamic> data, {int statusCode = 200}) {
    final responseBody = jsonEncode(data);
    context.log('Sending response (Status $statusCode): $responseBody'); // Log before sending
    return context.res.send(responseBody, statusCode: statusCode, headers: {'Content-Type': 'application/json'});
  }

  // --- 1. Initialize Appwrite Client ---
  final String apiKey = Platform.environment['APPWRITE_API_KEY'] ?? '';
  final String apiEndpoint = Platform.environment['APPWRITE_FUNCTION_API_ENDPOINT'] ?? '';
  final String projectId = Platform.environment['APPWRITE_FUNCTION_PROJECT_ID'] ?? '';

  // Use helper for error response
  if (apiKey.isEmpty || apiEndpoint.isEmpty || projectId.isEmpty) {
    context.error('Configuration Error: Missing API Key, Endpoint, or Project ID.');
    return sendJsonResponse({
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
  String requestBodyRaw = context.req.bodyRaw ?? ''; // Get raw body safely

  try {
     context.log('Raw request body received: $requestBodyRaw'); // Log the raw body

     if (requestBodyRaw.isEmpty) {
       context.log('Request body is empty.');
       // Use helper for error response
       return sendJsonResponse(
           {'success': false, 'error': 'Request body is empty'},
           statusCode: 400);
     }

     body = jsonDecode(requestBodyRaw); // Parse the raw string
     context.log('Parsed request body: $body'); // Log parsed body

     userId = body['userId'] as String?;
     action = body['action'] as String?;

     if (userId == null || userId.isEmpty) {
       context.log('Missing or empty "userId".');
       // Use helper for error response
       return sendJsonResponse({
         'success': false,
         'error': 'Missing or empty "userId" in request body.'
       }, statusCode: 400);
     }
     if (action == null || action != 'makeAdmin') {
       context.log('Missing or invalid action. Received: $action');
       // Use helper for error response
       return sendJsonResponse({
         'success': false,
         'error': 'Missing or invalid action. Supported: "makeAdmin".'
       }, statusCode: 400);
     }

   } catch (e, stackTrace) { // Catch specific error and stacktrace
     context.error('Failed to parse request body: $e\nStackTrace: $stackTrace');
     context.error('Original raw body was: $requestBodyRaw'); // Log raw body on error
     // Use helper for error response
     return sendJsonResponse(
         {'success': false, 'error': 'Invalid JSON format in request body.', 'details': e.toString()},
         statusCode: 400);
   }

  context.log('Attempting to add "admin" label to user (via prefs): $userId');

  // --- 3. Get User Prefs, Modify Labels, Update Prefs ---
  try {
    context.log('Fetching user preferences for $userId...');
    final Preferences prefs = await users.getPrefs(userId: userId);
    context.log('Successfully fetched user preferences for $userId.');

    List<String> currentLabels = [];
    if (prefs.data['labels'] is List) {
       currentLabels = List<String>.from(prefs.data['labels'].map((item) => item.toString()));
    } else if (prefs.data['labels'] != null) {
       context.log("Warning: 'labels' key in prefs exists but is not a List for user $userId.");
    }
     context.log('Current labels from prefs: $currentLabels');

    final Set<String> newLabelsSet = Set<String>.from(currentLabels);
    bool alreadyAdmin = newLabelsSet.contains('admin');

    if (alreadyAdmin) {
      context.log('User $userId already has the "admin" label in prefs.');
      // Use helper for success response
      return sendJsonResponse({
        'success': true,
        'message': 'User already has the admin label.',
        'userId': userId,
        'labels': currentLabels,
      });
    }

    newLabelsSet.add('admin');
    final List<String> updatedLabelsList = newLabelsSet.toList();
    context.log('Prepared updated labels list: $updatedLabelsList');

    // --- Using the more robust approach to preserve other prefs ---
    Map<String, dynamic> updatedPrefsData = Map<String, dynamic>.from(prefs.data); // Copy existing prefs
    updatedPrefsData['labels'] = updatedLabelsList; // Update/add the labels list
    context.log('Updating prefs with merged data: $updatedPrefsData');
    // --- END robust approach ---

    context.log('Attempting users.updatePrefs for $userId...');
    await users.updatePrefs(userId: userId, prefs: updatedPrefsData); // Use merged data
    context.log('users.updatePrefs call completed successfully for $userId.');

    context.log('Successfully added "admin" label via prefs logic for user: $userId');
    // Use helper for success response
    return sendJsonResponse({
      'success': true,
      'message': 'Admin label added successfully via prefs.',
      'userId': userId,
      'updatedLabels': updatedLabelsList,
    });

  } on AppwriteException catch (e) {
    context.error('Appwrite Error updating prefs for user $userId: [${e.code}] ${e.message} | Type: ${e.type} | Response: ${e.response}');
    int statusCode = 500;
    String errorMessage = 'Failed to update user prefs due to Appwrite error.';
    if (e.code == 404) { statusCode = 404; errorMessage = 'User not found with ID: $userId'; }
    // ... other specific error code handling ...
    final errorResponse = { 'success': false, 'error': errorMessage, 'details': e.message, 'code': e.code };
    context.log('Preparing to send Appwrite error response (Code: ${e.code})...');
    // Use helper for error response
    return sendJsonResponse(errorResponse, statusCode: statusCode);

  } catch (e, stackTrace) {
    context.error('Generic unexpected error updating prefs for user $userId: ${e.toString()}\nStackTrace: ${stackTrace}');
    final errorResponse = { 'success': false, 'error': 'An unexpected internal server error occurred.', 'details': e.toString() };
    context.log('Preparing to send generic error response...');
    // Use helper for error response
    return sendJsonResponse(errorResponse, statusCode: 500);
  }
}
