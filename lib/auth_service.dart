import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Stream of auth state changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Sign Up with Email and Password
  Future<Map<String, dynamic>> signUp({
    required String email,
    required String password,
    required String name,
  }) async {
    try {
      // Create user
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      User? user = result.user;

      if (user != null) {
        // Update display name
        await user.updateDisplayName(name);

        // Create user document in Firestore
        await _firestore.collection('users').doc(user.uid).set({
          'uid': user.uid,
          'email': email,
          'name': name,
          'createdAt': FieldValue.serverTimestamp(),
          'favoriteMovies': [],
          'watchlist': [],
        });

        // Save login state
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('isLoggedIn', true);
        await prefs.setString('userId', user.uid);

        return {
          'success': true,
          'message': 'Account created successfully!',
          'user': user,
        };
      }

      return {'success': false, 'message': 'Failed to create account'};
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'weak-password':
          message = 'Password is too weak. Use at least 6 characters.';
          break;
        case 'email-already-in-use':
          message = 'Email is already registered. Please login.';
          break;
        case 'invalid-email':
          message = 'Invalid email address format.';
          break;
        default:
          message = 'Registration failed: ${e.message}';
      }
      return {'success': false, 'message': message};
    } catch (e) {
      return {'success': false, 'message': 'An error occurred: $e'};
    }
  }

  // Sign In with Email and Password
  Future<Map<String, dynamic>> signIn({
    required String email,
    required String password,
  }) async {
    try {
      UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      User? user = result.user;

      if (user != null) {
        // Save login state
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('isLoggedIn', true);
        await prefs.setString('userId', user.uid);

        return {'success': true, 'message': 'Login successful!', 'user': user};
      }

      return {'success': false, 'message': 'Login failed'};
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'user-not-found':
          message = 'No account found with this email.';
          break;
        case 'wrong-password':
          message = 'Incorrect password.';
          break;
        case 'invalid-email':
          message = 'Invalid email address format.';
          break;
        case 'user-disabled':
          message = 'This account has been disabled.';
          break;
        default:
          message = 'Login failed: ${e.message}';
      }
      return {'success': false, 'message': message};
    } catch (e) {
      return {'success': false, 'message': 'An error occurred: $e'};
    }
  }

  // Sign Out
  Future<void> signOut() async {
    await _auth.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('isLoggedIn');
    await prefs.remove('userId');
  }

  // Reset Password
  Future<Map<String, dynamic>> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      return {
        'success': true,
        'message': 'Password reset email sent. Check your inbox.',
      };
    } on FirebaseAuthException catch (e) {
      return {
        'success': false,
        'message': e.message ?? 'Failed to send reset email',
      };
    }
  }

  // Check if user is logged in
  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('isLoggedIn') ?? false;
  }

  // Add movie to favorites
  Future<void> addToFavorites(
    String movieId,
    Map<String, dynamic> movieData,
  ) async {
    if (currentUser != null) {
      await _firestore.collection('users').doc(currentUser!.uid).update({
        'favoriteMovies': FieldValue.arrayUnion([
          {
            'imdbID': movieId,
            'title': movieData['Title'],
            'poster': movieData['Poster'],
            'year': movieData['Year'],
            'addedAt': FieldValue.serverTimestamp(),
          },
        ]),
      });
    }
  }

  // Remove from favorites
  Future<void> removeFromFavorites(String movieId) async {
    if (currentUser != null) {
      DocumentSnapshot doc =
          await _firestore.collection('users').doc(currentUser!.uid).get();
      List favorites = doc.get('favoriteMovies') ?? [];
      favorites.removeWhere((movie) => movie['imdbID'] == movieId);

      await _firestore.collection('users').doc(currentUser!.uid).update({
        'favoriteMovies': favorites,
      });
    }
  }

  // Get user favorites
  Future<List<dynamic>> getFavorites() async {
    if (currentUser != null) {
      DocumentSnapshot doc =
          await _firestore.collection('users').doc(currentUser!.uid).get();
      return doc.get('favoriteMovies') ?? [];
    }
    return [];
  }
}
