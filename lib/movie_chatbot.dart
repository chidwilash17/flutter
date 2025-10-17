import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

// Chat Message Model
class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
  });
}

// Enhanced Gemini AI Service with proper error handling
class GeminiAIService {
  static const String _apiKey =
      'AIzaSyAPewlECKqA9qa8vToKo7ZObCfPJsx710Q'; // Replace with your actual API key
  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-lite:generateContent';

  static Future<String> getMovieResponse(
    String query, {
    String? currentMovieTitle,
  }) async {
    try {
      final prompt = _buildPrompt(query, currentMovieTitle);

      print('🔍 Sending request to Gemini API...');

      final response = await http
          .post(
            Uri.parse('$_baseUrl?key=$_apiKey'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'contents': [
                {
                  'parts': [
                    {'text': prompt},
                  ],
                },
              ],
              'generationConfig': {
                'temperature': 0.7,
                'topK': 40,
                'topP': 0.95,
                'maxOutputTokens': 1024,
              },
              'safetySettings': [
                {
                  'category': 'HARM_CATEGORY_HARASSMENT',
                  'threshold': 'BLOCK_MEDIUM_AND_ABOVE',
                },
                {
                  'category': 'HARM_CATEGORY_HATE_SPEECH',
                  'threshold': 'BLOCK_MEDIUM_AND_ABOVE',
                },
                {
                  'category': 'HARM_CATEGORY_SEXUALLY_EXPLICIT',
                  'threshold': 'BLOCK_MEDIUM_AND_ABOVE',
                },
                {
                  'category': 'HARM_CATEGORY_DANGEROUS_CONTENT',
                  'threshold': 'BLOCK_MEDIUM_AND_ABOVE',
                },
              ],
            }),
          )
          .timeout(Duration(seconds: 30));

      print('📡 Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['candidates'] != null && data['candidates'].isNotEmpty) {
          final content = data['candidates'][0]['content']['parts'][0]['text'];
          return content;
        } else {
          throw Exception('No candidates in response');
        }
      } else {
        final errorData = json.decode(response.body);
        throw Exception(
          'API Error ${response.statusCode}: ${errorData['error']?['message'] ?? response.body}',
        );
      }
    } catch (e) {
      print('❌ Error calling Gemini API: $e');
      return _getFallbackResponse(query);
    }
  }

  static String _buildPrompt(String query, String? currentMovieTitle) {
    String context =
        currentMovieTitle != null
            ? "The user is currently viewing information about the movie '$currentMovieTitle'. "
            : "The user is browsing movies in general. ";

    return """
You are CineBot, an expert movie assistant in a mobile app called Movie Database Pro. $context

User Question: "$query"

Please provide a helpful, engaging response about movies. Follow these guidelines:
1. Keep responses concise but informative (2-4 paragraphs maximum)
2. Focus on movie recommendations, trivia, facts, or explanations
3. If discussing specific movies, include interesting details like ratings, year, cast
4. Be enthusiastic but accurate
5. If the query is not movie-related, politely redirect to movie topics
6. Use emojis occasionally to make it engaging (🎬 🍿 🎥 ⭐)
7. Format with clear paragraphs but no markdown
8. For director queries, mention their famous works
9. For genre queries, give 3-5 specific movie recommendations

Current capabilities of the app:
- Search movies by title or director
- Watch trailers in multiple languages (Hindi, Telugu, Tamil, English, etc.)
- Find full movies on YouTube
- Browse streaming platform links (Netflix, Prime, Hotstar)
- Get detailed movie information (cast, plot, ratings)
- CSV database with 50+ directors and their filmographies

Response:
""";
  }

  static String _getFallbackResponse(String query) {
    final queryLower = query.toLowerCase();

    // Context-aware fallback responses
    if (queryLower.contains('recommend') || queryLower.contains('suggest')) {
      return "🎬 I'd love to recommend some amazing films! Based on what's popular:\n\n" +
          "• **Action**: RRR, Pushpa, KGF 2\n" +
          "• **Hollywood**: Oppenheimer, Interstellar, The Dark Knight\n" +
          "• **Bollywood**: 3 Idiots, PK, Dunki\n\n" +
          "Try searching for any of these titles in the app to watch trailers and find where to stream them! 🍿";
    }

    if (queryLower.contains('director')) {
      return "🎥 Great directors in our database include:\n\n" +
          "• S.S. Rajamouli (RRR, Baahubali)\n" +
          "• Christopher Nolan (Oppenheimer, Inception)\n" +
          "• Sukumar (Pushpa, Rangasthalam)\n" +
          "• Rajkumar Hirani (3 Idiots, PK)\n\n" +
          "Search for any director name in the Directors tab to see their complete filmography! 🎬";
    }

    if (queryLower.contains('trailer') || queryLower.contains('watch')) {
      return "🎬 You can watch trailers for any movie in the app!\n\n" +
          "Features:\n" +
          "• Multi-language trailers (Hindi, Telugu, Tamil, English, etc.)\n" +
          "• Full movie search on YouTube\n" +
          "• Streaming platform links\n\n" +
          "Just search for a movie and tap on it to access all these features! 🍿";
    }

    // Default fallback
    return "🎬 I'm your movie expert! I can help you with:\n\n" +
        "• Movie recommendations by genre or language\n" +
        "• Director filmographies and best works\n" +
        "• Movie trivia and behind-the-scenes facts\n" +
        "• Where to watch (Netflix, Prime, Hotstar)\n" +
        "• Cast information and ratings\n\n" +
        "What would you like to know about movies? 🍿";
  }
}

// Enhanced MovieChatBot with better error handling
class MovieChatBot extends StatefulWidget {
  final dynamic currentMovie;
  final VoidCallback onClose;

  const MovieChatBot({Key? key, this.currentMovie, required this.onClose})
    : super(key: key);

  @override
  _MovieChatBotState createState() => _MovieChatBotState();
}

class _MovieChatBotState extends State<MovieChatBot>
    with SingleTickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  final ScrollController _scrollController = ScrollController();
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 300),
    );
    _animationController.forward();
    _addWelcomeMessage();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _scrollController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _addWelcomeMessage() {
    String welcomeText =
        widget.currentMovie != null
            ? """🎬 Hello! I'm CineBot!

I see you're viewing "${widget.currentMovie['Title']}". I can tell you more about this movie, recommend similar films, or answer any movie-related questions!

What would you like to know? 🍿"""
            : """🎬 Hello! I'm CineBot, your AI movie expert!

I can help you with:
• Movie recommendations & reviews
• Director filmographies
• Movie trivia & facts
• Streaming suggestions
• Language-specific films
• And anything about cinema!

What would you like to explore? 🍿""";

    _messages.add(
      ChatMessage(text: welcomeText, isUser: false, timestamp: DateTime.now()),
    );
    _scrollToBottom();
  }

  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add(
        ChatMessage(text: text, isUser: true, timestamp: DateTime.now()),
      );
      _messageController.clear();
      _isLoading = true;
    });
    _scrollToBottom();

    try {
      final response = await GeminiAIService.getMovieResponse(
        text,
        currentMovieTitle: widget.currentMovie?['Title'],
      );

      if (mounted) {
        setState(() {
          _messages.add(
            ChatMessage(
              text: response,
              isUser: false,
              timestamp: DateTime.now(),
            ),
          );
          _isLoading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      print('Error in chat: $e');
      if (mounted) {
        setState(() {
          _messages.add(
            ChatMessage(
              text:
                  "I apologize for the technical difficulty! 🛠️\n\nMeanwhile, feel free to:\n• Search movies by title or director\n• Watch trailers in multiple languages\n• Check streaming platforms\n• Explore our director database\n\nTry asking me another question! 🎬",
              isUser: false,
              timestamp: DateTime.now(),
            ),
          );
          _isLoading = false;
        });
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showQuickQuestions() {
    final quickQuestions =
        widget.currentMovie != null
            ? [
              "Tell me more about ${widget.currentMovie['Title']}",
              "Recommend similar movies",
              "Who directed this movie?",
              "What's the plot about?",
              "Where can I watch this?",
            ]
            : [
              "Recommend action movies",
              "Best Christopher Nolan films",
              "Top Indian cinema picks",
              "Movies with amazing visuals",
              "Classic Hollywood must-watch",
              "Latest Telugu blockbusters",
            ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (context) => Container(
            padding: EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.lightbulb, color: Colors.amber, size: 24),
                    SizedBox(width: 8),
                    Text(
                      'Quick Questions',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 4),
                Text(
                  'Tap any question to ask CineBot:',
                  style: TextStyle(color: Colors.grey[400], fontSize: 13),
                ),
                SizedBox(height: 12),
                ...quickQuestions
                    .map(
                      (question) => Card(
                        color: Colors.grey[800],
                        margin: EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Icon(
                            Icons.chat_bubble_outline,
                            color: Colors.red,
                            size: 18,
                          ),
                          title: Text(
                            question,
                            style: TextStyle(color: Colors.white, fontSize: 14),
                          ),
                          trailing: Icon(
                            Icons.arrow_forward,
                            color: Colors.grey,
                            size: 16,
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            _messageController.text = question;
                            _sendMessage();
                          },
                        ),
                      ),
                    )
                    .toList(),
              ],
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: Tween<Offset>(begin: Offset(0, 1), end: Offset.zero).animate(
        CurvedAnimation(
          parent: _animationController,
          curve: Curves.easeOutCubic,
        ),
      ),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(25),
            topRight: Radius.circular(25),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 15,
              offset: Offset(0, -3),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFE50914), Color(0xFFB20710)],
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(25),
                  topRight: Radius.circular(25),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.smart_toy,
                      color: Color(0xFFE50914),
                      size: 24,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CineBot Assistant',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          'AI Movie Expert • Powered by Gemini',
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.lightbulb_outline, color: Colors.white),
                    onPressed: _showQuickQuestions,
                    tooltip: 'Quick Questions',
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.white),
                    onPressed: widget.onClose,
                  ),
                ],
              ),
            ),

            // Messages
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: EdgeInsets.all(16),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final message = _messages[index];
                  return ChatBubble(message: message);
                },
              ),
            ),

            // Loading Indicator
            if (_isLoading)
              Container(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Color(0xFFE50914),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.smart_toy,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'CineBot is thinking...',
                        style: TextStyle(color: Colors.grey[400], fontSize: 13),
                      ),
                    ),
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Color(0xFFE50914),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Input Area
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[850],
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 5,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[800],
                        borderRadius: BorderRadius.circular(25),
                        border: Border.all(color: Colors.grey[700]!),
                      ),
                      child: TextField(
                        controller: _messageController,
                        style: TextStyle(color: Colors.white),
                        maxLines: null,
                        decoration: InputDecoration(
                          hintText: 'Ask about movies, directors, genres...',
                          hintStyle: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 13,
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              Icons.emoji_emotions_outlined,
                              color: Colors.grey[500],
                            ),
                            onPressed: _showQuickQuestions,
                          ),
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                  ),
                  SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFFE50914), Color(0xFFB20710)],
                      ),
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: IconButton(
                      icon: Icon(Icons.send, color: Colors.white),
                      onPressed: _sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Enhanced ChatBubble with better styling
class ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const ChatBubble({Key? key, required this.message}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!message.isUser)
            Container(
              margin: EdgeInsets.only(right: 8),
              padding: EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Color(0xFFE50914),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.smart_toy, color: Colors.white, size: 16),
            ),
          Flexible(
            child: Column(
              crossAxisAlignment:
                  message.isUser
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    gradient:
                        message.isUser
                            ? LinearGradient(
                              colors: [Colors.blue[700]!, Colors.blue[800]!],
                            )
                            : null,
                    color: message.isUser ? null : Colors.grey[800],
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(message.isUser ? 16 : 4),
                      bottomRight: Radius.circular(message.isUser ? 4 : 16),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 3,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    message.text,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ),
                SizedBox(height: 4),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    _formatTime(message.timestamp),
                    style: TextStyle(color: Colors.grey[600], fontSize: 10),
                  ),
                ),
              ],
            ),
          ),
          if (message.isUser)
            Container(
              margin: EdgeInsets.only(left: 8),
              padding: EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.blue,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.person, color: Colors.white, size: 16),
            ),
        ],
      ),
    );
  }

  String _formatTime(DateTime timestamp) {
    return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
  }
}
