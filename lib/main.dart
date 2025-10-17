import 'package:firebase_auth/firebase_auth.dart';

import 'movie_chatbot.dart';
import 'package:flutter/material.dart';

import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:csv/csv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'login_screen.dart';
import 'register_screen.dart';
import 'auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Movie Database Pro',
      theme: ThemeData.dark().copyWith(
        primaryColor: Color(0xFF1E1E2E),
        scaffoldBackgroundColor: Color(0xFF0D0D0D),
        colorScheme: ColorScheme.dark(
          primary: Color(0xFFE50914),
          secondary: Color(0xFF00D9FF),
        ),
      ),
      debugShowCheckedModeBanner: false,
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Scaffold(
              backgroundColor: Color(0xFF0D0D0D),
              body: Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(Color(0xFFE50914)),
                ),
              ),
            );
          }

          if (snapshot.hasData && snapshot.data != null) {
            return MovieListScreen();
          }

          return LoginScreen();
        },
      ),
      routes: {
        '/login': (context) => LoginScreen(),
        '/register': (context) => RegisterScreen(),
        '/home': (context) => MovieListScreen(),
      },
    );
  }
}

class MovieListScreen extends StatefulWidget {
  @override
  _MovieListScreenState createState() => _MovieListScreenState();
}

class _MovieListScreenState extends State<MovieListScreen>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  List<dynamic> movies = [];
  List<dynamic> directors = [];
  Map<String, List<dynamic>> directorCache = {};
  bool isLoading = false;
  late TextEditingController searchController;
  String currentSearch = '';
  late TabController _tabController;
  String selectedLanguage = 'All';

  // NEW: CSV Director-Movie mapping
  Map<String, List<String>> csvDirectorMovies = {};
  Map<String, String> csvDirectorIndustry = {};
  List<String> csvAllDirectors = [];
  List<String> csvFilteredDirectors = [];
  List<dynamic> teluguMovies = [];
  List<dynamic> hindiMovies = [];
  List<dynamic> englishMovies = [];
  bool isLoadingHome = true;
  bool csvShowSuggestions = false;
  bool csvIsLoaded = false;

  // API Keys
  final String omdbApiKey = '';
  final String youtubeApiKey = '';

  // Language options
  final List<String> languages = [
    'All',
    'Hindi',
    'Telugu',
    'Tamil',
    'Malayalam',
    'Kannada',
    'English',
    'Korean',
    'Japanese',
    'Chinese',
  ];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    searchController = TextEditingController();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_handleTabChange);
    _loadCSV();
    _loadHomeMovies(); // NEW: Load home screen movies
    // NEW: Load CSV on startup
  }

  void _handleTabChange() {
    if (!mounted) return;
    setState(() {
      csvShowSuggestions = false;
    });
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    searchController.dispose();
    super.dispose();
  }

  // NEW: Load CSV file
  Future<void> _loadCSV() async {
    try {
      print('🔄 Loading directors_movies_complete.csv...');

      final csvString = await rootBundle.loadString(
        'assets/directors_movies_complete.csv',
      );
      List<List<dynamic>> csvTable = CsvToListConverter().convert(csvString);

      Map<String, List<String>> tempDirectorMovies = {};
      Map<String, String> tempDirectorIndustry = {};

      for (int i = 1; i < csvTable.length; i++) {
        final row = csvTable[i];

        String directorName = row[1].toString();
        String movieTitle = row[2].toString();
        String industry = row[3].toString();

        if (!tempDirectorMovies.containsKey(directorName)) {
          tempDirectorMovies[directorName] = [];
          tempDirectorIndustry[directorName] = industry;
        }

        tempDirectorMovies[directorName]!.add(movieTitle);
      }

      setState(() {
        csvDirectorMovies = tempDirectorMovies;
        csvDirectorIndustry = tempDirectorIndustry;
        csvAllDirectors = tempDirectorMovies.keys.toList()..sort();
        csvIsLoaded = true;
      });

      print(
        '✅ Loaded ${csvAllDirectors.length} directors with ${csvTable.length - 1} movies',
      );
    } catch (e) {
      print('⚠️ CSV not found, using API search only: $e');
      setState(() {
        csvIsLoaded = false;
      });
    }
  }

  // NEW: Load random popular movies for home screen
  Future<void> _loadHomeMovies() async {
    try {
      print('🏠 Loading home screen movies...');

      final teluguKeywords = ['pushpa', 'rrr', 'baahubali', 'kgf', 'salaar'];
      final hindiKeywords = ['3 idiots', 'pk', 'dangal', 'pathaan', 'jawan'];
      final englishKeywords = [
        'avatar',
        'oppenheimer',
        'inception',
        'interstellar',
        'titanic',
      ];

      final teluguResults = await _fetchMoviesByKeywords(teluguKeywords);
      final hindiResults = await _fetchMoviesByKeywords(hindiKeywords);
      final englishResults = await _fetchMoviesByKeywords(englishKeywords);

      if (mounted) {
        setState(() {
          teluguMovies = teluguResults;
          hindiMovies = hindiResults;
          englishMovies = englishResults;
          isLoadingHome = false;
        });
        print('✅ Home movies loaded');
      }
    } catch (e) {
      print('❌ Error loading home movies: $e');
      if (mounted) {
        setState(() {
          isLoadingHome = false;
        });
      }
    }
  }

  Future<List<dynamic>> _fetchMoviesByKeywords(List<String> keywords) async {
    List<dynamic> results = [];

    for (String keyword in keywords) {
      try {
        final response = await http
            .get(
              Uri.parse(
                'http://www.omdbapi.com/?t=${Uri.encodeComponent(keyword)}&apikey=$omdbApiKey',
              ),
            )
            .timeout(Duration(seconds: 20));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['Response'] == 'True') {
            results.add(data);
          }
        }
        await Future.delayed(Duration(milliseconds: 300));
      } catch (e) {
        print('Error fetching $keyword: $e');
      }
    }

    return results;
  }

  // NEW: Filter directors from CSV for autocomplete
  void _filterCSVDirectors(String query) {
    if (query.isEmpty || !csvIsLoaded) {
      setState(() {
        csvFilteredDirectors = [];
        csvShowSuggestions = false;
      });
      return;
    }

    setState(() {
      csvFilteredDirectors =
          csvAllDirectors
              .where((d) => d.toLowerCase().contains(query.toLowerCase()))
              .take(10)
              .toList();
      csvShowSuggestions =
          csvFilteredDirectors.isNotEmpty && _tabController.index == 1;
    });
  }

  Future<void> fetchMovies(String query) async {
    if (query.isEmpty || !mounted) return;

    print('🎬 Fetching MOVIES for: $query');

    setState(() {
      isLoading = true;
      currentSearch = query;
      movies = []; // Clear previous results
    });

    try {
      String searchQuery =
          selectedLanguage != 'All'
              ? '$query ${selectedLanguage.toLowerCase()}'
              : query;

      final response = await http
          .get(
            Uri.parse(
              'http://www.omdbapi.com/?s=${Uri.encodeComponent(searchQuery)}&type=movie&apikey=$omdbApiKey',
            ),
          )
          .timeout(Duration(seconds: 15));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('📡 API Response: ${data['Response']}');

        if (data['Response'] == 'True' && data['Search'] != null) {
          print('✅ Found ${data['Search'].length} movies');

          if (mounted) {
            setState(() {
              movies = data['Search'];
              isLoading = false;
            });
          }
        } else {
          print('❌ No movies found');
          if (mounted) {
            setState(() {
              movies = [];
              isLoading = false;
            });
            _showErrorSnackBar('No movies found for "$query"');
          }
        }
      }
    } catch (e) {
      print('❌ Error fetching movies: $e');
      if (mounted) {
        setState(() {
          isLoading = false;
          movies = [];
        });
        _showErrorSnackBar('Network error. Please check your connection.');
      }
    }
  }

  // ENHANCED: Fetch movies with language filter (UNCHANGED)

  // ENHANCED: Director search - FIRST try CSV, then fallback to API
  Future<void> fetchDirectorMovies(String directorName) async {
    if (directorName.isEmpty || !mounted) return;

    setState(() {
      isLoading = true;
      currentSearch = directorName;
      directors = [];
      csvShowSuggestions = false;
    });

    // Check cache first
    if (directorCache.containsKey(directorName.toLowerCase())) {
      if (mounted) {
        setState(() {
          directors = directorCache[directorName.toLowerCase()]!;
          isLoading = false;
        });
        _showSuccessSnackBar('✓ Loaded from cache');
      }
      return;
    }

    // NEW: Try CSV first
    if (csvIsLoaded && csvDirectorMovies.containsKey(directorName)) {
      await _fetchDirectorMoviesFromCSV(directorName);
      return;
    }

    // Fallback to API search (your existing implementation)
    await _fetchDirectorMoviesFromAPI(directorName);
  }

  // NEW: Fetch director movies from CSV + OMDB enrichment
  Future<void> _fetchDirectorMoviesFromCSV(String directorName) async {
    if (!mounted) return;

    List<String> movieTitles = csvDirectorMovies[directorName]!;
    List<dynamic> enrichedMovies = [];

    print(
      '🎬 Fetching ${movieTitles.length} movies for $directorName from CSV...',
    );

    for (int i = 0; i < movieTitles.length && i < 20; i++) {
      if (!mounted) break;

      String movieTitle = movieTitles[i];
      print('   [${i + 1}/${movieTitles.length}] $movieTitle');

      try {
        final response = await http
            .get(
              Uri.parse(
                'http://www.omdbapi.com/?t=${Uri.encodeComponent(movieTitle)}&apikey=$omdbApiKey',
              ),
            )
            .timeout(Duration(seconds: 5));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['Response'] == 'True') {
            enrichedMovies.add({...data, 'Director': directorName});
          } else {
            enrichedMovies.add({
              'Title': movieTitle,
              'Year': 'N/A',
              'Poster': 'N/A',
              'Director': directorName,
              'imdbID': 'N/A',
            });
          }
        }
      } catch (e) {
        enrichedMovies.add({
          'Title': movieTitle,
          'Year': 'N/A',
          'Poster': 'N/A',
          'Director': directorName,
          'imdbID': 'N/A',
        });
      }

      await Future.delayed(Duration(milliseconds: 300));
    }

    // Cache results
    if (enrichedMovies.isNotEmpty) {
      directorCache[directorName.toLowerCase()] = [
        {
          'name': directorName,
          'movies': enrichedMovies,
          'biography':
              '${csvDirectorIndustry[directorName] ?? "Film"} Director',
          'image': '',
          'movieCount': enrichedMovies.length,
        },
      ];
    }

    setState(() {
      directors =
          enrichedMovies.isNotEmpty
              ? [
                {
                  'name': directorName,
                  'movies': enrichedMovies,
                  'biography':
                      '${csvDirectorIndustry[directorName] ?? "Film"} Director',
                  'image': '',
                  'movieCount': enrichedMovies.length,
                },
              ]
              : [];
      isLoading = false;
    });

    if (enrichedMovies.isNotEmpty) {
      _showSuccessSnackBar(
        '🎬 Found ${enrichedMovies.length} movies from CSV!',
      );
    } else {
      _showErrorSnackBar('No movies found');
    }

    print('✅ Loaded ${enrichedMovies.length} movies from CSV');
  }

  // EXISTING: API-based director search (UNCHANGED - fallback)
  Future<void> _fetchDirectorMoviesFromAPI(String directorName) async {
    if (!mounted) return;

    try {
      print('🎬 Searching for director: $directorName');

      List<dynamic> allMovies = [];
      Set<String> uniqueImdbIds = {};

      // Search with just director name
      try {
        final response = await http
            .get(
              Uri.parse(
                'http://www.omdbapi.com/?s=${Uri.encodeComponent(directorName)}&type=movie&apikey=$omdbApiKey',
              ),
            )
            .timeout(Duration(seconds: 15)); // Increased timeout

        if (mounted && response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['Response'] == 'True' && data['Search'] != null) {
            allMovies.addAll(data['Search']);
            print('✅ Found ${data['Search'].length} movies');
          }
        }
      } catch (e) {
        print('⚠️ Search attempt failed: $e');
      }

      if (allMovies.isEmpty) {
        if (mounted) {
          setState(() {
            directors = [];
            isLoading = false;
          });
          _showErrorSnackBar(
            'No movies found for "$directorName". Try searching for movie titles instead.',
          );
        }
        return;
      }

      // Get details for each movie
      List<dynamic> directorMovies = [];

      for (var movie in allMovies.take(10)) {
        // Limit to 10 movies
        if (!mounted) break;
        if (uniqueImdbIds.contains(movie['imdbID'])) continue;
        uniqueImdbIds.add(movie['imdbID']);

        try {
          final details = await _fetchMovieDetails(movie['imdbID']);

          if (mounted && details != null && details['Director'] != null) {
            String movieDirector = details['Director'].toString().toLowerCase();
            String searchDirector = directorName.toLowerCase();

            // Check if director name matches
            if (movieDirector.contains(searchDirector) ||
                searchDirector
                    .split(' ')
                    .any(
                      (part) => part.length > 2 && movieDirector.contains(part),
                    )) {
              directorMovies.add({
                ...movie,
                'details': details,
                'Director': details['Director'],
                'Year': details['Year'],
                'imdbRating': details['imdbRating'],
                'Runtime': details['Runtime'],
                'Genre': details['Genre'],
              });
            }
          }

          await Future.delayed(
            Duration(milliseconds: 500),
          ); // Slower to avoid throttling
        } catch (e) {
          print('⚠️ Error processing movie: $e');
        }
      }

      // Sort by year
      directorMovies.sort((a, b) {
        try {
          int yearA = int.parse(
            a['Year'].toString().replaceAll(RegExp(r'[^\d]'), ''),
          );
          int yearB = int.parse(
            b['Year'].toString().replaceAll(RegExp(r'[^\d]'), ''),
          );
          return yearB.compareTo(yearA);
        } catch (e) {
          return 0;
        }
      });

      // Cache results
      if (directorMovies.isNotEmpty) {
        directorCache[directorName.toLowerCase()] = [
          {
            'name': directorName,
            'movies': directorMovies,
            'biography': 'Film Director',
            'image': '',
            'movieCount': directorMovies.length,
          },
        ];
      }

      if (mounted) {
        setState(() {
          directors =
              directorMovies.isNotEmpty
                  ? [
                    {
                      'name': directorName,
                      'movies': directorMovies,
                      'biography': 'Film Director',
                      'image': '',
                      'movieCount': directorMovies.length,
                    },
                  ]
                  : [];
          isLoading = false;
        });

        if (directorMovies.isEmpty) {
          _showErrorSnackBar('No movies found for "$directorName"');
        } else {
          _showSuccessSnackBar(
            '✓ Found ${directorMovies.length} movies by $directorName',
          );
        }
      }
    } catch (e) {
      print('❌ Error in director search: $e');
      if (mounted) {
        setState(() {
          isLoading = false;
          directors = [];
        });
        _showErrorSnackBar('Network error. Check internet connection.');
      }
    }
  }

  // Fetch detailed movie information from OMDB (UNCHANGED)
  Future<Map<String, dynamic>?> _fetchMovieDetails(String imdbId) async {
    try {
      final response = await http
          .get(
            Uri.parse(
              'http://www.omdbapi.com/?i=$imdbId&plot=full&apikey=$omdbApiKey',
            ),
          )
          .timeout(Duration(seconds: 25));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['Response'] == 'True') {
          return data;
        }
      }
    } catch (e) {
      print('Error fetching details for $imdbId: $e');
    }
    return null;
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.error, color: Colors.white),
            SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _search(String query) {
    if (query.isEmpty || !mounted) return;

    // Check which tab we're on
    if (_tabController.index == 1) {
      // Movies tab - search for movies
      print('🎬 Searching MOVIES for: $query');
      fetchMovies(query);
    } else if (_tabController.index == 2) {
      // Directors tab - search for directors
      print('👤 Searching DIRECTORS for: $query');
      fetchDirectorMovies(query);
    } else {
      // Home tab - don't search
      _showErrorSnackBar('Please go to Movies or Directors tab to search');
    }
  }

  Widget _buildLanguageFilter() {
    return Container(
      height: 55,
      margin: EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 12),
        itemCount: languages.length,
        itemBuilder: (context, index) {
          final language = languages[index];
          final isSelected = selectedLanguage == language;
          return Padding(
            padding: EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(language),
              selected: isSelected,
              onSelected: (bool selected) {
                if (mounted) {
                  setState(() {
                    selectedLanguage = language;
                  });
                  if (currentSearch.isNotEmpty && _tabController.index == 0) {
                    fetchMovies(currentSearch);
                  }
                }
              },
              backgroundColor: Colors.grey[850],
              selectedColor: Colors.blue,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : Colors.grey[300],
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
              checkmarkColor: Colors.white,
              elevation: isSelected ? 4 : 0,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('Movie Database Pro'),
        backgroundColor: Colors.black,
        actions: [
          // NEW: Show CSV status badge
          if (csvIsLoaded)
            Padding(
              padding: EdgeInsets.only(right: 8),
              child: Center(
                child: Chip(
                  label: Text('${csvAllDirectors.length}D CSV'),
                  backgroundColor: Colors.green.withOpacity(0.2),
                  labelStyle: TextStyle(color: Colors.green, fontSize: 10),
                ),
              ),
            ),
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: () {
              if (_tabController.index == 0) {
                _loadHomeMovies();
              } else if (currentSearch.isNotEmpty) {
                _search(currentSearch);
              }
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Color(0xFFE50914),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.grey,
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.home, size: 20),
                  SizedBox(width: 6),
                  Text('Home'),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.movie, size: 20),
                  SizedBox(width: 6),
                  Text('Movies'),
                ],
              ),
            ),

            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person, size: 20),
                  SizedBox(width: 6),
                  Text('Directors'),
                ],
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildHomeTab(), // ADD THIS - Home tab
          _buildMoviesTab(), // Movies tab
          _buildDirectorsTab(), // Directors tab
        ],
      ),

      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder:
                (context) => MovieChatBot(
                  currentMovie: null,
                  onClose: () => Navigator.pop(context),
                ),
          );
        },
        icon: Icon(Icons.smart_toy),
        label: Text('CineBot'),
        backgroundColor: Color(0xFFE50914),
        heroTag: 'cinebot',
      ),
    );
  }

  // NEW: Home Tab with Random Movies
  Widget _buildHomeTab() {
    return isLoadingHome
        ? Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(Color(0xFFE50914)),
              ),
              SizedBox(height: 16),
              Text(
                'Loading featured movies...',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        )
        : SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Welcome Banner
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFE50914), Color(0xFFB20710)],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '🎬 Welcome to Movie Database Pro',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Discover movies from around the world',
                      style: TextStyle(fontSize: 14, color: Colors.white70),
                    ),
                  ],
                ),
              ),

              if (teluguMovies.isNotEmpty) ...[
                SizedBox(height: 20),
                _buildMovieSection(
                  '🎭 Telugu Cinema',
                  teluguMovies,
                  Colors.orange,
                ),
              ],

              if (hindiMovies.isNotEmpty) ...[
                SizedBox(height: 20),
                _buildMovieSection(
                  '🎪 Bollywood Hits',
                  hindiMovies,
                  Colors.green,
                ),
              ],

              if (englishMovies.isNotEmpty) ...[
                SizedBox(height: 20),
                _buildMovieSection(
                  '🎥 Hollywood Blockbusters',
                  englishMovies,
                  Colors.blue,
                ),
              ],

              SizedBox(height: 80),
            ],
          ),
        );
  }

  Widget _buildMovieSection(
    String title,
    List<dynamic> movies,
    Color accentColor,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 24,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 12),
        Container(
          height: 280,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: 16),
            itemCount: movies.length,
            itemBuilder: (context, index) {
              final movie = movies[index];
              return GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder:
                          (context) => MovieDetailScreen(
                            movie: movie,
                            omdbApiKey: omdbApiKey,
                            youtubeApiKey: youtubeApiKey,
                          ),
                    ),
                  );
                },
                child: Container(
                  width: 150,
                  margin: EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: accentColor.withOpacity(0.3),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(12),
                          ),
                          child:
                              movie['Poster'] != 'N/A'
                                  ? CachedNetworkImage(
                                    imageUrl: movie['Poster'],
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                  )
                                  : Container(color: Colors.grey[850]),
                        ),
                      ),
                      Container(
                        padding: EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.grey[900],
                          borderRadius: BorderRadius.vertical(
                            bottom: Radius.circular(12),
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              movie['Title'],
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.star, size: 12, color: Colors.amber),
                                SizedBox(width: 2),
                                Text(
                                  movie['imdbRating'] ?? 'N/A',
                                  style: TextStyle(
                                    color: Colors.amber,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // [REST OF THE CODE CONTINUES WITH YOUR EXACT IMPLEMENTATION]
  // _buildMoviesTab(), _buildDirectorsTab(), etc. - ALL UNCHANGED
  // Just add the CSV autocomplete in _buildDirectorsTab()

  Widget _buildMoviesTab() {
    // YOUR EXISTING CODE - UNCHANGED
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[900],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Color(0xFFE50914).withOpacity(0.3),
                    ),
                  ),
                  child: TextField(
                    controller: searchController,
                    style: TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search movies... (e.g., avatar, kgf, pushpa)',
                      hintStyle: TextStyle(color: Colors.grey[500]),
                      border: InputBorder.none,
                      prefixIcon: Icon(Icons.search, color: Color(0xFFE50914)),
                      suffixIcon:
                          searchController.text.isNotEmpty
                              ? IconButton(
                                icon: Icon(Icons.clear, color: Colors.grey),
                                onPressed: () {
                                  if (mounted) {
                                    searchController.clear();
                                    setState(() {
                                      movies = [];
                                      currentSearch = '';
                                    });
                                  }
                                },
                              )
                              : null,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                    onSubmitted: _search,
                    onChanged: (value) {
                      if (mounted) setState(() {});
                    },
                  ),
                ),
              ),
              SizedBox(width: 10),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFE50914), Color(0xFFB20710)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _search(searchController.text),
                    child: Padding(
                      padding: EdgeInsets.all(14),
                      child: Icon(Icons.search, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select Language:',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              _buildLanguageFilter(),
            ],
          ),
        ),

        if (currentSearch.isNotEmpty && _tabController.index == 0)
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Color(0xFFE50914).withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Color(0xFFE50914).withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.movie, color: Color(0xFFE50914), size: 18),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$selectedLanguage Movies: "$currentSearch"',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 13,
                    ),
                  ),
                ),
                if (!isLoading)
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${movies.length}',
                      style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                if (isLoading)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Color(0xFFE50914)),
                    ),
                  ),
              ],
            ),
          ),

        Expanded(
          child:
              isLoading
                  ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation(Color(0xFFE50914)),
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Searching $selectedLanguage movies...',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                  : movies.isEmpty
                  ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Color(0xFFE50914).withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.movie_creation,
                            size: 60,
                            color: Color(0xFFE50914),
                          ),
                        ),
                        SizedBox(height: 20),
                        Text(
                          'No $selectedLanguage movies found',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 10),
                        Text(
                          'Try: "bahubali", "rrr", "pushpa", "avatar"',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                  : ListView.builder(
                    padding: EdgeInsets.all(16),
                    itemCount: movies.length,
                    itemBuilder: (context, index) {
                      return MovieCard(
                        movie: movies[index],
                        omdbApiKey: omdbApiKey,
                        youtubeApiKey: youtubeApiKey,
                      );
                    },
                  ),
        ),
      ],
    );
  }

  Widget _buildDirectorsTab() {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[900],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue.withOpacity(0.3)),
                      ),
                      child: TextField(
                        controller: searchController,
                        style: TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText:
                              'Search directors... (e.g., rajamouli, nolan)',
                          hintStyle: TextStyle(color: Colors.grey[500]),
                          border: InputBorder.none,
                          prefixIcon: Icon(
                            Icons.person_search,
                            color: Colors.blue,
                          ),
                          suffixIcon:
                              searchController.text.isNotEmpty
                                  ? IconButton(
                                    icon: Icon(Icons.clear, color: Colors.grey),
                                    onPressed: () {
                                      if (mounted) {
                                        searchController.clear();
                                        setState(() {
                                          directors = [];
                                          currentSearch = '';
                                          csvShowSuggestions = false;
                                        });
                                      }
                                    },
                                  )
                                  : null,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                        onSubmitted: _search,
                        onChanged: (value) {
                          if (mounted) {
                            setState(() {});
                            _filterCSVDirectors(value); // NEW: Autocomplete
                          }
                        },
                      ),
                    ),
                  ),
                  SizedBox(width: 10),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.blue, Colors.blue[700]!],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _search(searchController.text),
                        child: Padding(
                          padding: EdgeInsets.all(14),
                          child: Icon(Icons.search, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // NEW: CSV Autocomplete Dropdown
              if (csvShowSuggestions && csvFilteredDirectors.isNotEmpty)
                Container(
                  margin: EdgeInsets.only(top: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey[850],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  constraints: BoxConstraints(maxHeight: 200),
                  child: ListView.builder(
                    itemCount: movies.length,
                    itemBuilder: (context, idx) {
                      var movie = movies[idx];

                      String? poster = movie['Poster'];
                      String title = movie['Title'] ?? '[No Title]';
                      String year = movie['Year'] ?? 'Unknown Year';

                      return ListTile(
                        leading:
                            (poster != null && poster != 'N/A')
                                ? Image.network(poster, width: 50)
                                : Icon(Icons.movie),
                        title: Text(title),
                        subtitle: Text(year),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),

        // YOUR EXISTING STATUS BANNER
        if (currentSearch.isNotEmpty && _tabController.index == 1)
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.blue.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.person, color: Colors.blue, size: 18),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Director: "$currentSearch"',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 13,
                    ),
                  ),
                ),
                if (!isLoading && directors.isNotEmpty)
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${directors[0]['movieCount'] ?? directors[0]['movies'].length}',
                      style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                if (isLoading)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.blue),
                    ),
                  ),
              ],
            ),
          ),

        // YOUR EXISTING CONTENT
        Expanded(
          child:
              isLoading
                  ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation(Colors.blue),
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Searching director filmography...',
                          style: TextStyle(color: Colors.grey),
                        ),
                        SizedBox(height: 8),
                        Text(
                          csvIsLoaded
                              ? 'Using CSV + OMDB...'
                              : 'Fetching from OMDB API...',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  )
                  : directors.isEmpty
                  ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.person_search,
                            size: 60,
                            color: Colors.blue,
                          ),
                        ),
                        SizedBox(height: 20),
                        Text(
                          'Search for Directors',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 10),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 40),
                          child: Text(
                            csvIsLoaded
                                ? '${csvAllDirectors.length} directors available in database'
                                : 'Enter director name to search',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                        SizedBox(height: 20),
                        Wrap(
                          spacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            _buildSuggestionChip('S.S. Rajamouli'),
                            _buildSuggestionChip('Christopher Nolan'),
                            _buildSuggestionChip('James Cameron'),
                          ],
                        ),
                      ],
                    ),
                  )
                  : ListView.builder(
                    padding: EdgeInsets.all(16),
                    itemCount: directors.length,
                    itemBuilder: (context, index) {
                      return DirectorCard(
                        director: directors[index],
                        omdbApiKey: omdbApiKey,
                        youtubeApiKey: youtubeApiKey,
                      );
                    },
                  ),
        ),
      ],
    );
  }

  Widget _buildSuggestionChip(String suggestion) {
    return ActionChip(
      label: Text(suggestion, style: TextStyle(fontSize: 12)),
      onPressed: () {
        searchController.text = suggestion;
        _search(suggestion);
      },
      backgroundColor: Colors.white.withOpacity(0.05),
      labelStyle: TextStyle(color: Colors.white),
      side: BorderSide(color: Colors.blue.withOpacity(0.5)),
    );
  }
}

// [ALL YOUR EXISTING WIDGETS: MovieCard, DirectorCard, MovieDetailScreen - COMPLETELY UNCHANGED]
// MOVIE CARD WIDGET (YOUR ORIGINAL)
class MovieCard extends StatelessWidget {
  final dynamic movie;
  final String omdbApiKey;
  final String youtubeApiKey;

  const MovieCard({
    Key? key,
    required this.movie,
    required this.omdbApiKey,
    required this.youtubeApiKey,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1E1E2E), Color(0xFF2A2A3E)],
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder:
                    (context) => MovieDetailScreen(
                      movie: movie,
                      omdbApiKey: omdbApiKey,
                      youtubeApiKey: youtubeApiKey,
                    ),
              ),
            );
          },
          child: Padding(
            padding: EdgeInsets.all(10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Hero(
                  tag: 'movie_${movie['imdbID']}',
                  child: Container(
                    width: 90,
                    height: 135,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0xFFE50914).withOpacity(0.2),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child:
                          movie['Poster'] != null && movie['Poster'] != 'N/A'
                              ? CachedNetworkImage(
                                imageUrl: movie['Poster'],
                                fit: BoxFit.cover,
                                placeholder:
                                    (context, url) => Container(
                                      color: Colors.grey[850],
                                      child: Center(
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation(
                                            Color(0xFFE50914),
                                          ),
                                        ),
                                      ),
                                    ),
                                errorWidget:
                                    (context, url, error) => Container(
                                      color: Colors.grey[850],
                                      child: Icon(
                                        Icons.movie,
                                        color: Colors.white54,
                                      ),
                                    ),
                              )
                              : Container(
                                color: Colors.grey[850],
                                child: Icon(Icons.movie, color: Colors.white54),
                              ),
                    ),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        movie['Title'] ?? 'Unknown',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontSize: 15,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 6),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Color(0xFFE50914).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          movie['Year'] ?? 'N/A',
                          style: TextStyle(
                            color: Color(0xFFE50914),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Type: ${movie['Type'] ?? 'movie'}',
                        style: TextStyle(color: Colors.grey, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 14,
                  color: Color(0xFFE50914),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// DIRECTOR CARD WIDGET (YOUR ORIGINAL)
class DirectorCard extends StatelessWidget {
  final dynamic director;
  final String omdbApiKey;
  final String youtubeApiKey;

  const DirectorCard({
    Key? key,
    required this.director,
    required this.omdbApiKey,
    required this.youtubeApiKey,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final movies = director['movies'] as List<dynamic>? ?? [];

    return Card(
      margin: EdgeInsets.only(bottom: 16),
      elevation: 6,
      color: Color(0xFF1E1E2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.person, size: 32, color: Colors.blue),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        director['name'] ?? 'Unknown Director',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '${movies.length} Movies Found',
                        style: TextStyle(color: Colors.green, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            if (movies.isNotEmpty) ...[
              Text(
                'Filmography:',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 12),
              GridView.builder(
                shrinkWrap: true,
                physics: NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 0.65,
                ),
                itemCount: movies.length,
                itemBuilder: (context, index) {
                  final movie = movies[index];
                  return GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder:
                              (context) => MovieDetailScreen(
                                movie: movie,
                                omdbApiKey: omdbApiKey,
                                youtubeApiKey: youtubeApiKey,
                              ),
                        ),
                      );
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[850],
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(10),
                              ),
                              child:
                                  movie['Poster'] != null &&
                                          movie['Poster'] != 'N/A'
                                      ? CachedNetworkImage(
                                        imageUrl: movie['Poster'],
                                        fit: BoxFit.cover,
                                        width: double.infinity,
                                        placeholder:
                                            (context, url) => Container(
                                              color: Colors.grey[800],
                                              child: Center(
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              ),
                                            ),
                                        errorWidget:
                                            (context, url, error) => Container(
                                              color: Colors.grey[800],
                                              child: Icon(
                                                Icons.movie,
                                                color: Colors.white54,
                                              ),
                                            ),
                                      )
                                      : Container(
                                        color: Colors.grey[800],
                                        child: Icon(
                                          Icons.movie,
                                          color: Colors.white54,
                                        ),
                                      ),
                            ),
                          ),
                          Container(
                            padding: EdgeInsets.all(6),
                            child: Column(
                              children: [
                                Text(
                                  movie['Title'] ?? 'Unknown',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                ),
                                SizedBox(height: 2),
                                Text(
                                  movie['Year'] ?? 'N/A',
                                  style: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 9,
                                  ),
                                ),
                                if (movie['imdbRating'] != null &&
                                    movie['imdbRating'] != 'N/A')
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.star,
                                        color: Colors.amber,
                                        size: 10,
                                      ),
                                      SizedBox(width: 2),
                                      Text(
                                        movie['imdbRating'],
                                        style: TextStyle(
                                          color: Colors.amber,
                                          fontSize: 9,
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ] else
              Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.movie_creation, size: 40, color: Colors.grey),
                      SizedBox(height: 8),
                      Text(
                        'No movies found',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// MOVIE DETAIL SCREEN (YOUR COMPLETE ORIGINAL WITH ALL FEATURES)
class MovieDetailScreen extends StatefulWidget {
  final dynamic movie;
  final String omdbApiKey;
  final String youtubeApiKey;

  const MovieDetailScreen({
    Key? key,
    required this.movie,
    required this.omdbApiKey,
    required this.youtubeApiKey,
  }) : super(key: key);

  @override
  _MovieDetailScreenState createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends State<MovieDetailScreen>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  Map<String, dynamic>? movieDetails;
  bool isLoading = true;
  bool isTrailerLoading = false;
  bool isFullMovieLoading = false;
  YoutubePlayerController? _youtubeController;
  YoutubePlayerController? _fullMovieController;
  bool showYouTubePlayer = false;
  bool showFullMoviePlayer = false;
  String searchStatus = '';
  String fullMovieStatus = '';
  List<StreamingService> streamingServices = [];
  late TabController _tabController;

  String selectedTrailerLanguage = 'English';
  final List<String> trailerLanguages = [
    'Hindi',
    'Telugu',
    'Tamil',
    'Malayalam',
    'Kannada',
    'English',
    'Korean',
    'Japanese',
    'Chinese',
  ];

  String selectedMovieLanguage = 'English';

  final Map<String, List<String>> _languageTrailerKeywords = {
    'Hindi': ['hindi trailer', 'bollywood trailer', 'hindi official trailer'],
    'Telugu': [
      'telugu trailer',
      'tollywood trailer',
      'telugu official trailer',
    ],
    'Tamil': ['tamil trailer', 'kollywood trailer', 'tamil official trailer'],
    'Malayalam': ['malayalam trailer', 'mollywood trailer'],
    'Kannada': ['kannada trailer', 'sandalwood trailer'],
    'English': ['english trailer', 'hollywood trailer', 'official trailer'],
    'Korean': ['korean trailer', 'k-drama trailer'],
    'Japanese': ['japanese trailer', 'anime trailer'],
    'Chinese': ['chinese trailer', 'mandarin trailer'],
  };

  final Map<String, List<String>> _languageMovieKeywords = {
    'Hindi': ['hindi full movie', 'bollywood movie'],
    'Telugu': ['telugu full movie', 'tollywood movie'],
    'Tamil': ['tamil full movie', 'kollywood movie'],
    'Malayalam': ['malayalam full movie', 'mollywood movie'],
    'Kannada': ['kannada full movie', 'sandalwood movie'],
    'English': ['english full movie', 'hollywood movie', 'full movie'],
    'Korean': ['korean full movie', 'korean movie'],
    'Japanese': ['japanese full movie', 'japanese movie'],
    'Chinese': ['chinese full movie', 'chinese movie'],
  };

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    fetchMovieDetails();
    _initializeStreamingServices();
  }

  @override
  void dispose() {
    _youtubeController?.close();
    _fullMovieController?.close();
    _tabController.dispose();
    super.dispose();
  }

  void _initializeStreamingServices() {
    streamingServices = [
      StreamingService(
        name: 'Netflix',
        icon: Icons.play_circle_filled,
        color: Colors.red,
        baseUrl: 'https://www.netflix.com/search?q=',
      ),
      StreamingService(
        name: 'Amazon Prime',
        icon: Icons.video_library,
        color: Colors.blue,
        baseUrl: 'https://www.primevideo.com/search/ref=atv_nb_sr?phrase=',
      ),
      StreamingService(
        name: 'Disney+ Hotstar',
        icon: Icons.star,
        color: Colors.blue,
        baseUrl: 'https://www.hotstar.com/in/search?q=',
      ),
      StreamingService(
        name: 'YouTube Movies',
        icon: Icons.play_circle_filled,
        color: Colors.red,
        baseUrl: 'https://www.youtube.com/results?search_query=',
      ),
    ];
  }

  Future<void> fetchMovieDetails() async {
    if (!mounted) return;

    try {
      final response = await http
          .get(
            Uri.parse(
              'http://www.omdbapi.com/?i=${widget.movie['imdbID']}&plot=full&apikey=${widget.omdbApiKey}',
            ),
          )
          .timeout(Duration(seconds: 10));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) {
          setState(() {
            movieDetails = data;
            isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  int? _getMovieRuntime() {
    if (movieDetails == null || movieDetails!['Runtime'] == 'N/A') return null;

    try {
      final runtimeStr = movieDetails!['Runtime'];
      final minutes = int.tryParse(runtimeStr.replaceAll(' min', ''));
      return minutes;
    } catch (e) {
      return null;
    }
  }

  Future<String?> _findBestTrailer() async {
    try {
      final languageKeywords =
          _languageTrailerKeywords[selectedTrailerLanguage] ??
          ['official trailer'];

      for (final keyword in languageKeywords) {
        final query =
            '${widget.movie['Title']} ${widget.movie['Year']} $keyword';

        if (mounted) {
          setState(() {
            searchStatus = 'Searching $selectedTrailerLanguage trailer...';
          });
        }

        final videoId = await _searchYouTube(query);
        if (videoId != null) return videoId;

        await Future.delayed(Duration(milliseconds: 500));
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<String?> _findFullMovie() async {
    try {
      final languageKeywords =
          _languageMovieKeywords[selectedMovieLanguage] ?? ['full movie'];

      for (final keyword in languageKeywords) {
        final query =
            '${widget.movie['Title']} ${widget.movie['Year']} $keyword';

        if (mounted) {
          setState(() {
            fullMovieStatus = 'Searching $selectedMovieLanguage movie...';
          });
        }

        final videoId = await _searchYouTube(query);
        if (videoId != null) return videoId;

        await Future.delayed(Duration(milliseconds: 500));
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<String?> _searchYouTube(String query) async {
    try {
      final response = await http
          .get(
            Uri.parse(
              'https://www.googleapis.com/youtube/v3/search?'
              'part=snippet&q=${Uri.encodeComponent(query)}&'
              'type=video&maxResults=5&key=${widget.youtubeApiKey}',
            ),
          )
          .timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['items'] != null && data['items'].isNotEmpty) {
          return data['items'][0]['id']['videoId'];
        }
      }
    } catch (e) {
      print('YouTube search error: $e');
    }
    return null;
  }

  Future<void> _playTrailer() async {
    if (!mounted) return;

    setState(() {
      isTrailerLoading = true;
    });

    final videoId = await _findBestTrailer();

    if (!mounted) return;

    if (videoId != null) {
      setState(() {
        _youtubeController = YoutubePlayerController(
          params: YoutubePlayerParams(showControls: true, mute: false),
        )..loadVideoById(videoId: videoId);
        showYouTubePlayer = true;
        isTrailerLoading = false;
      });
      _showSuccessSnackBar('🎬 Playing $selectedTrailerLanguage Trailer');
    } else {
      setState(() {
        isTrailerLoading = false;
      });
      _showErrorSnackBar('No $selectedTrailerLanguage trailer found');
    }
  }

  Future<void> _findAndPlayFullMovie() async {
    if (!mounted) return;

    setState(() {
      isFullMovieLoading = true;
    });

    final videoId = await _findFullMovie();

    if (!mounted) return;

    if (videoId != null) {
      setState(() {
        _fullMovieController = YoutubePlayerController(
          params: YoutubePlayerParams(showControls: true, mute: false),
        )..loadVideoById(videoId: videoId);
        showFullMoviePlayer = true;
        isFullMovieLoading = false;
      });
      _showSuccessSnackBar('🎥 $selectedMovieLanguage Movie Available');
    } else {
      setState(() {
        isFullMovieLoading = false;
      });
      _showInfoSnackBar('No $selectedMovieLanguage movie found');
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showInfoSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.blue,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  Widget _buildTrailerLanguageSelector() {
    return Container(
      height: 50,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: trailerLanguages.length,
        itemBuilder: (context, index) {
          final language = trailerLanguages[index];
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: Text(language),
              selected: selectedTrailerLanguage == language,
              onSelected: (selected) {
                if (mounted) {
                  setState(() {
                    selectedTrailerLanguage = language;
                  });
                }
              },
              backgroundColor: Colors.grey[800],
              selectedColor: Colors.orange,
              labelStyle: TextStyle(
                color:
                    selectedTrailerLanguage == language
                        ? Colors.white
                        : Colors.grey[300],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMovieLanguageSelector() {
    return Container(
      height: 50,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: trailerLanguages.length,
        itemBuilder: (context, index) {
          final language = trailerLanguages[index];
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: Text(language),
              selected: selectedMovieLanguage == language,
              onSelected: (selected) {
                if (mounted) {
                  setState(() {
                    selectedMovieLanguage = language;
                  });
                }
              },
              backgroundColor: Colors.grey[800],
              selectedColor: Colors.green,
              labelStyle: TextStyle(
                color:
                    selectedMovieLanguage == language
                        ? Colors.white
                        : Colors.grey[300],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(movieDetails?['Title'] ?? widget.movie['Title']),
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            icon: Icon(Icons.chat),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder:
                    (context) => MovieChatBot(
                      currentMovie: widget.movie,
                      onClose: () => Navigator.pop(context),
                    ),
              );
            },
            tooltip: 'ASk CineBot',
          ),
          IconButton(icon: Icon(Icons.refresh), onPressed: fetchMovieDetails),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Color(0xFFE50914),
          tabs: [
            Tab(icon: Icon(Icons.info), text: 'Details'),
            Tab(icon: Icon(Icons.play_arrow), text: 'Videos'),
            Tab(icon: Icon(Icons.stream), text: 'Streaming'),
          ],
        ),
      ),
      body:
          isLoading
              ? Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(Color(0xFFE50914)),
                ),
              )
              : Stack(
                children: [
                  TabBarView(
                    controller: _tabController,
                    children: [
                      _buildDetailsTab(),
                      _buildVideosTab(),
                      _buildStreamingTab(),
                    ],
                  ),
                  if (showYouTubePlayer && _youtubeController != null)
                    _buildVideoPlayer(
                      _youtubeController!,
                      '$selectedTrailerLanguage Trailer',
                      () {
                        if (mounted) {
                          setState(() {
                            showYouTubePlayer = false;
                          });
                        }
                      },
                    ),
                  if (showFullMoviePlayer && _fullMovieController != null)
                    _buildVideoPlayer(
                      _fullMovieController!,
                      '$selectedMovieLanguage Movie',
                      () {
                        if (mounted) {
                          setState(() {
                            showFullMoviePlayer = false;
                          });
                        }
                      },
                    ),
                ],
              ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder:
                (context) => MovieChatBot(
                  currentMovie: null,
                  onClose: () => Navigator.pop(context),
                ),
          );
        },
        icon: Icon(Icons.smart_toy),
        label: Text('CineBot'),
        backgroundColor: Color(0xFFE50914),
      ),
    );
  }

  Widget _buildDetailsTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMovieHeader(),
          SizedBox(height: 20),
          if (movieDetails!['Plot'] != 'N/A') _buildPlotSection(),
          SizedBox(height: 20),
          _buildAdditionalInfo(),
        ],
      ),
    );
  }

  Widget _buildVideosTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          Card(
            color: Colors.grey[900],
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '🎬 Select Trailer Language:',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 12),
                  _buildTrailerLanguageSelector(),
                  SizedBox(height: 16),
                  if (isTrailerLoading)
                    Column(
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 10),
                        Text(
                          searchStatus,
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    )
                  else
                    ElevatedButton.icon(
                      onPressed: _playTrailer,
                      icon: Icon(Icons.play_circle_filled),
                      label: Text('Play $selectedTrailerLanguage Trailer'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        minimumSize: Size(double.infinity, 50),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SizedBox(height: 20),
          Card(
            color: Colors.grey[900],
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '🎥 Select Movie Language:',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 12),
                  _buildMovieLanguageSelector(),
                  SizedBox(height: 16),
                  if (isFullMovieLoading)
                    Column(
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 10),
                        Text(
                          fullMovieStatus,
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    )
                  else
                    ElevatedButton.icon(
                      onPressed: _findAndPlayFullMovie,
                      icon: Icon(Icons.movie),
                      label: Text('Find $selectedMovieLanguage Movie'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        minimumSize: Size(double.infinity, 50),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStreamingTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Card(
        color: Colors.grey[900],
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Stream on Platforms',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children:
                    streamingServices.map((service) {
                      return ActionChip(
                        avatar: Icon(service.icon, color: service.color),
                        label: Text(service.name),
                        onPressed: () => _launchStreamingService(service),
                        backgroundColor: Colors.grey[800],
                        labelStyle: TextStyle(color: Colors.white),
                      );
                    }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoPlayer(
    YoutubePlayerController controller,
    String title,
    VoidCallback onClose,
  ) {
    return Container(
      color: Colors.black,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.white),
                    onPressed: onClose,
                  ),
                ],
              ),
            ),
            Expanded(
              child: YoutubePlayer(controller: controller, aspectRatio: 16 / 9),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMovieHeader() {
    final runtime = _getMovieRuntime();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (movieDetails!['Poster'] != null && movieDetails!['Poster'] != 'N/A')
          CachedNetworkImage(
            imageUrl: movieDetails!['Poster'],
            height: 180,
            fit: BoxFit.cover,
            placeholder:
                (context, url) => Container(
                  height: 180,
                  width: 120,
                  color: Colors.grey[800],
                  child: Center(child: CircularProgressIndicator()),
                ),
            errorWidget:
                (context, url, error) => Container(
                  height: 180,
                  width: 120,
                  color: Colors.grey[800],
                  child: Icon(Icons.movie, size: 48, color: Colors.white54),
                ),
          ),
        SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                movieDetails!['Title'] ?? widget.movie['Title'],
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (movieDetails!['Year'] != null)
                    Chip(
                      label: Text('${movieDetails!['Year']}'),
                      backgroundColor: Colors.grey[800],
                    ),
                  if (runtime != null)
                    Chip(
                      label: Text('${runtime}min'),
                      backgroundColor: Colors.purple[800],
                    ),
                  if (movieDetails!['imdbRating'] != null &&
                      movieDetails!['imdbRating'] != 'N/A')
                    Chip(
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.star, color: Colors.amber, size: 16),
                          SizedBox(width: 4),
                          Text('${movieDetails!['imdbRating']}'),
                        ],
                      ),
                      backgroundColor: Colors.amber[800]?.withOpacity(0.3),
                    ),
                ],
              ),
              SizedBox(height: 8),
              if (movieDetails!['Genre'] != null &&
                  movieDetails!['Genre'] != 'N/A')
                Text(
                  'Genre: ${movieDetails!['Genre']}',
                  style: TextStyle(color: Colors.grey),
                ),
              if (movieDetails!['Director'] != null &&
                  movieDetails!['Director'] != 'N/A')
                Text(
                  'Director: ${movieDetails!['Director']}',
                  style: TextStyle(color: Colors.blue, fontSize: 12),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPlotSection() {
    return Card(
      color: Colors.grey[900],
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Storyline',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 8),
            Text(
              movieDetails!['Plot'],
              style: TextStyle(color: Colors.white70, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdditionalInfo() {
    return Card(
      color: Colors.grey[900],
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Additional Information',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 12),
            if (movieDetails!['Director'] != null &&
                movieDetails!['Director'] != 'N/A')
              _buildInfoRow('Director', movieDetails!['Director']),
            if (movieDetails!['Actors'] != null &&
                movieDetails!['Actors'] != 'N/A')
              _buildInfoRow('Cast', movieDetails!['Actors']),
            if (movieDetails!['Language'] != null &&
                movieDetails!['Language'] != 'N/A')
              _buildInfoRow('Language', movieDetails!['Language']),
            if (movieDetails!['Country'] != null &&
                movieDetails!['Country'] != 'N/A')
              _buildInfoRow('Country', movieDetails!['Country']),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _launchStreamingService(StreamingService service) async {
    final movieTitle = widget.movie['Title'];
    final encodedTitle = Uri.encodeComponent('$movieTitle movie');
    final url = '${service.baseUrl}$encodedTitle';

    try {
      if (await canLaunch(url)) {
        await launch(url);
      } else {
        _showErrorSnackBar('Could not launch ${service.name}');
      }
    } catch (e) {
      _showErrorSnackBar('Error launching ${service.name}');
    }
  }
}

class StreamingService {
  final String name;
  final IconData icon;
  final Color color;
  final String baseUrl;

  StreamingService({
    required this.name,
    required this.icon,
    required this.color,
    required this.baseUrl,
  });
}
