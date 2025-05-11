import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'dart:convert';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Orientacde portret
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]).then((_) {
    runApp(
      ChangeNotifierProvider(
        create: (context) => WeatherProvider(),
        child: const MyApp(),
      ),
    );
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Počasíčko',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Roboto',
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}

// Provider pro správu stavu aplikace
class WeatherProvider extends ChangeNotifier {
  bool _isLoading = true;
  String _errorMessage = '';
  String _city = 'Praha';
  String _country = 'CZ';
  String _formattedDate = '';
  double _temperature = 0;
  String _weatherCondition = '';
  List<DailyForecast> _dailyForecast = [];
  String _temperatureUnit = '°C';
  bool _useGps = true;

  bool get isLoading => _isLoading;
  String get errorMessage => _errorMessage;
  String get city => _city;
  String get country => _country;
  String get formattedDate => _formattedDate;
  String get temperature => '${_temperature.round()}°';
  String get weatherCondition => _weatherCondition;
  List<DailyForecast> get dailyForecast => _dailyForecast;
  String get temperatureUnit => _temperatureUnit;
  bool get useGps => _useGps;

  WeatherProvider() {
    _loadPreferences();
  }

  // Načtení uloženýh nastavrní
  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _city = prefs.getString('city') ?? 'Praha';
      _temperatureUnit = prefs.getString('temperatureUnit') ?? '°C';
      _useGps = prefs.getBool('useGps') ?? true;
      notifyListeners();
      fetchWeatherData();
    } catch (e) {
      _errorMessage = 'Chyba při načítání nastavení: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  // Změna města
  Future<void> setCity(String city) async {
    _city = city;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('city', city);
      notifyListeners();
      fetchWeatherData();
    } catch (e) {
      _errorMessage = 'Chyba při ukládání města: $e';
      notifyListeners();
    }
  }

  // Změna jednotky teploty
  Future<void> setTemperatureUnit(String unit) async {
    _temperatureUnit = unit;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('temperatureUnit', unit);
      notifyListeners();
      fetchWeatherData();
    } catch (e) {
      _errorMessage = 'Chyba při ukládání jednotky teploty: $e';
      notifyListeners();
    }
  }

  // Změna použití GPS
  Future<void> setUseGps(bool value) async {
    _useGps = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('useGps', value);
      notifyListeners();
      if (value) {
        getCurrentLocation();
      } else {
        fetchWeatherData();
      }
    } catch (e) {
      _errorMessage = 'Chyba při ukládání použití GPS: $e';
      notifyListeners();
    }
  }

  // Získání aktuální polohy pomocí GPS
  Future<void> getCurrentLocation() async {
    _isLoading = true;
    _errorMessage = '';
    notifyListeners();

    try {
      // Kontrola oprávnění k poloze
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _errorMessage = 'Oprávnění k poloze bylo zamítnuto';
          _isLoading = false;
          _useGps = false;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('useGps', false);
          notifyListeners();
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _errorMessage = 'Oprávnění k poloze bylo trvale zamítnuto';
        _isLoading = false;
        _useGps = false;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('useGps', false);
        notifyListeners();
        return;
      }

      // Získání pozice
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      await fetchWeatherDataByCoordinates(position.latitude, position.longitude);
    } catch (e) {
      _errorMessage = 'Chyba při získávání polohy: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  // Získání dat o počasí podle města
  Future<void> fetchWeatherData() async {
    if (_useGps) {
      await getCurrentLocation();
      return;
    }

    _isLoading = true;
    _errorMessage = '';
    notifyListeners();

    try {
      // API klíč pro OpenWeatherMap
      const apiKey = '4d8fb5b93d4af21d66a2948710284366';

      // Formát jednotky teploty pro API
      final units = _temperatureUnit == '°C' ? 'metric' : 'imperial';

      // Nastavení lokalizace (češtiny) pro správné formátování dat
      await initializeDateFormatting('cs_CZ', null);

      // API volání pro aktuální počásko
      final currentWeatherUrl = Uri.parse(
          'https://api.openweathermap.org/data/2.5/weather?q=$_city&appid=$apiKey&units=$units&lang=cz'
      );

      final currentWeatherResponse = await http.get(currentWeatherUrl);

      if (currentWeatherResponse.statusCode == 200) {
        final currentWeatherData = json.decode(currentWeatherResponse.body);

        // Aktualizace dat o aktuálním počásku
        _city = currentWeatherData['name'];
        _country = currentWeatherData['sys']['country'];
        _temperature = currentWeatherData['main']['temp'].toDouble();
        _weatherCondition = currentWeatherData['weather'][0]['description'];
        _weatherCondition = _weatherCondition[0].toUpperCase() + _weatherCondition.substring(1);

        // Formátování aktuálního data
        _formattedDate = DateFormat('EEEE, d MMMM', 'cs_CZ').format(DateTime.now());

        // API volání pro předpověď na 5 dní
        final forecastUrl = Uri.parse(
            'https://api.openweathermap.org/data/2.5/forecast?q=$_city&appid=$apiKey&units=$units&lang=cz'
        );

        final forecastResponse = await http.get(forecastUrl);

        if (forecastResponse.statusCode == 200) {
          final forecastData = json.decode(forecastResponse.body);
          _processForecastData(forecastData);
        } else {
          _errorMessage = 'Chyba při získávání předpovědi: ${forecastResponse.statusCode}';
        }
      } else {
        _errorMessage = 'Město nenalezeno';
      }
    } catch (e) {
      _errorMessage = 'Chyba při získávání dat o počasí: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Získání dat o počásku podle souřadnic
  Future<void> fetchWeatherDataByCoordinates(double lat, double lon) async {
    try {
      const apiKey = '4d8fb5b93d4af21d66a2948710284366';
      final units = _temperatureUnit == '°C' ? 'metric' : 'imperial';

      // Nastavení lokalizace (češtiny) pro správné formátování data
      await initializeDateFormatting('cs_CZ', null);

      // API volání pro aktuální počasí podle souřadnic
      final currentWeatherUrl = Uri.parse(
          'https://api.openweathermap.org/data/2.5/weather?lat=$lat&lon=$lon&appid=$apiKey&units=$units&lang=cz'
      );

      final currentWeatherResponse = await http.get(currentWeatherUrl);

      if (currentWeatherResponse.statusCode == 200) {
        final currentWeatherData = json.decode(currentWeatherResponse.body);

        _city = currentWeatherData['name'];
        _country = currentWeatherData['sys']['country'];
        _temperature = currentWeatherData['main']['temp'].toDouble();
        _weatherCondition = currentWeatherData['weather'][0]['description'];
        _weatherCondition = _weatherCondition[0].toUpperCase() + _weatherCondition.substring(1);

        _formattedDate = DateFormat('EEEE, d MMMM', 'cs_CZ').format(DateTime.now());

        // API volání pro předpověď na 5 dní podle souřadnic
        final forecastUrl = Uri.parse(
            'https://api.openweathermap.org/data/2.5/forecast?lat=$lat&lon=$lon&appid=$apiKey&units=$units&lang=cz'
        );

        final forecastResponse = await http.get(forecastUrl);

        if (forecastResponse.statusCode == 200) {
          final forecastData = json.decode(forecastResponse.body);
          _processForecastData(forecastData);
        }
      }
    } catch (e) {
      _errorMessage = 'Chyba při získávání dat o počasí: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Zpracování dat o předpovědi
  void _processForecastData(Map<String, dynamic> forecastData) {
    final List<dynamic> forecastList = forecastData['list'];

    // Získání jedinečných dnů z předpovědi
    final Map<String, DailyForecast> dailyData = {};

    for (var item in forecastList) {
      final dateTime = DateTime.fromMillisecondsSinceEpoch(item['dt'] * 1000);
      final day = DateFormat('yyyy-MM-dd').format(dateTime);

      if (!dailyData.containsKey(day)) {
        dailyData[day] = DailyForecast(
          date: dateTime,
          highTemp: item['main']['temp_max'].toDouble(),
          lowTemp: item['main']['temp_min'].toDouble(),
          condition: item['weather'][0]['main'],
          icon: _getWeatherIcon(item['weather'][0]['icon']),
        );
      } else {
        // Aktualizace min/max teploty
        if (item['main']['temp_max'] > dailyData[day]!.highTemp) {
          dailyData[day]!.highTemp = item['main']['temp_max'].toDouble();
        }
        if (item['main']['temp_min'] < dailyData[day]!.lowTemp) {
          dailyData[day]!.lowTemp = item['main']['temp_min'].toDouble();
        }
      }
    }

    // Převedení na seznam a seřazení podle data
    _dailyForecast = dailyData.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));

// Omezení na příštích 5 dní
    if (_dailyForecast.length > 5) {
      _dailyForecast = _dailyForecast.sublist(0, 5);
    }
  }

  // Získání ikony počasí podle kódu z API
  IconData _getWeatherIcon(String iconCode) {
    switch (iconCode.substring(0, 2)) {
      case '01': return Icons.wb_sunny_outlined; // sluníčko
      case '02': return Icons.cloud_queue; // polojasno
      case '03':
      case '04': return Icons.cloud_outlined; // oblačno
      case '09': return Icons.grain; // přeháňky
      case '10': return Icons.water_drop_outlined; // déšť
      case '11': return Icons.thunderstorm_outlined; // bouřky
      case '13': return Icons.ac_unit_outlined; // sníh
      case '50': return Icons.foggy; // mlha
      default: return Icons.help_outline; // neznámé
    }
  }
}

// Model pro denní předpověď
class DailyForecast {
  final DateTime date;
  double highTemp;
  double lowTemp;
  final String condition;
  final IconData icon;

  DailyForecast({
    required this.date,
    required this.highTemp,
    required this.lowTemp,
    required this.condition,
    required this.icon,
  });

  String get dayOfWeek => DateFormat('E', 'cs_CZ').format(date);
  String get formattedHighTemp => '${highTemp.round()}°';
  String get formattedLowTemp => '${lowTemp.round()}°';
}

// Hlavní obrazovka s navigaccí
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

// swipe navigace

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final PageController _pageController = PageController();

  final List<Widget> _screens = const [
    CurrentWeatherScreen(),
    ForecastScreen(),
    SettingsScreen(),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        children: _screens,
        physics: const BouncingScrollPhysics(), // Hezčí animace při swipe
      ),
      //  bottomNavigationBar
    );
  }
}

// Widget pro pozadí s gradientem
class RadialGradientBackground extends StatelessWidget {
  final Widget child;

  const RadialGradientBackground({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(-0.5, 0.0),
          radius: 1.2,
          colors: [
            Colors.pink.shade300,
            Colors.pink.shade100.withOpacity(0.7),
            Colors.white.withOpacity(0.9),
          ],
          stops: const [0.2, 0.5, 0.9],
        ),
      ),
      child: child,
    );
  }
}

// Widget ikona vyhledávání
class SimpleSearchIcon extends StatelessWidget {
  final double size;
  final Color color;

  const SimpleSearchIcon({
    super.key,
    this.size = 24.0,
    this.color = Colors.black,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _SearchIconPainter(color: color),
      ),
    );
  }
}

// Ikona vyhleddávní
class _SearchIconPainter extends CustomPainter {
  final Color color;

  _SearchIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // \Tělo lupy
    final center = Offset(size.width * 0.4, size.height * 0.4);
    final radius = size.width * 0.3;
    canvas.drawCircle(center, radius, paint);

    // tyčka lupy
    final start = Offset(center.dx + radius * 0.7, center.dy + radius * 0.7);
    final end = Offset(size.width * 0.8, size.height * 0.8);
    canvas.drawLine(start, end, paint);
  }

  @override
  bool shouldRepaint(_SearchIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

// 1. Obrazovka: Aktuální počasí
class CurrentWeatherScreen extends StatelessWidget {
  const CurrentWeatherScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<WeatherProvider>(
      builder: (context, weatherProvider, child) {
        if (weatherProvider.isLoading) {
          return const Center(child: CircularProgressIndicator(color: Colors.pink));
        }

        // Získání předpovědi na 3 dny
        final dailyForecast = weatherProvider.dailyForecast.length > 3
            ? weatherProvider.dailyForecast.sublist(0, 3)
            : weatherProvider.dailyForecast;

        return RadialGradientBackground(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  // Horní lišta
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GestureDetector(
                        onTap: () => _showSearchDialog(context),
                        child: SimpleSearchIcon(
                          size: 28,
                          color: Colors.black.withOpacity(0.6),
                        ),
                      ),
                      Icon(
                        Icons.more_vert,
                        size: 24,
                        color: Colors.black.withOpacity(0.6),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Město a datum
                  Text(
                    weatherProvider.city,  // bez ", CZ"
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    weatherProvider.formattedDate,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.black.withOpacity(0.6),
                    ),
                  ),
                  // Chybová zpráva, pokud existuje
                  if (weatherProvider.errorMessage.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 16.0),
                      child: Text(
                        weatherProvider.errorMessage,
                        style: const TextStyle(
                          color: Colors.red,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  // Volný prostor
                  const Spacer(),
                  // Teplota (levý dolní roh)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        weatherProvider.temperature,
                        style: const TextStyle(
                          fontSize: 100,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        weatherProvider.weatherCondition,
                        style: TextStyle(
                          fontSize: 20,
                          color: Colors.black.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Oddělující čára
                  Divider(
                    color: Colors.black.withOpacity(0.2),
                    thickness: 2,
                  ),
                  const SizedBox(height: 16),
                  // Předpověď na další dny
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: dailyForecast.isEmpty
                        ? [const Text('Žádná data k dispozici')]
                        : dailyForecast.map((forecast) => _buildDayForecast(forecast)).toList(),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDayForecast(DailyForecast forecast) {
    return Column(
      children: [
        Text(
          forecast.dayOfWeek,
          style: TextStyle(
            fontSize: 14,
            color: Colors.black.withOpacity(0.7),
          ),
        ),
        const SizedBox(height: 8),
        Icon(
          forecast.icon,
          size: 24,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              forecast.formattedHighTemp,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.0),
              child: Text(
                "|",
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.black.withOpacity(0.4),
                  fontWeight: FontWeight.w300,
                ),
              ),
            ),
            Text(
              forecast.formattedLowTemp,
              style: TextStyle(
                fontSize: 14,
                color: Colors.black.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Dialog pro vyhledávání města
  void _showSearchDialog(BuildContext context) {
    final TextEditingController controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hledat město'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Zadejte název města'),
          onSubmitted: (value) {
            if (value.isNotEmpty) {
              Provider.of<WeatherProvider>(context, listen: false)
                  .setCity(value);
              Navigator.of(context).pop();
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Zrušit'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                Provider.of<WeatherProvider>(context, listen: false)
                    .setCity(controller.text);
                Navigator.of(context).pop();
              }
            },
            child: const Text('Hledat'),
          ),
        ],
      ),
    );
  }
}

// 2. Obrazovka: Týdenní předpověď
class ForecastScreen extends StatelessWidget {
  const ForecastScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<WeatherProvider>(
      builder: (context, weatherProvider, child) {
        if (weatherProvider.isLoading) {
          return const Center(child: CircularProgressIndicator(color: Colors.pink));
        }

        return RadialGradientBackground(
          child: SafeArea(
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(20.0),
                  child: Text(
                    'Předpověď na pět dní',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                ),
                if (weatherProvider.errorMessage.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: Text(
                      weatherProvider.errorMessage,
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 14,
                      ),
                    ),
                  ),
                Expanded(
                  child: weatherProvider.dailyForecast.isEmpty
                      ? const Center(child: Text('Žádná data k dispozici'))
                      : ListView.builder(
                    itemCount: weatherProvider.dailyForecast.length,
                    itemBuilder: (context, index) {
                      final forecast = weatherProvider.dailyForecast[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        elevation: 0,
                        color: Colors.white.withOpacity(0.7),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    forecast.dayOfWeek,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(DateFormat('d.M.', 'cs_CZ').format(forecast.date)),
                                ],
                              ),
                              Icon(
                                forecast.icon,
                                size: 24,
                              ),
                              Row(
                                children: [
                                  Text(
                                    forecast.formattedHighTemp,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    "|",
                                    style: TextStyle(
                                      color: Colors.black.withOpacity(0.4),
                                      fontWeight: FontWeight.w300,
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    forecast.formattedLowTemp,
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// 3. Obrazovka: Nastavení
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<WeatherProvider>(
      builder: (context, weatherProvider, child) {
        return RadialGradientBackground(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Nastavení',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Card(
                    elevation: 0,
                    color: Colors.white.withOpacity(0.7),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Lokalita',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _buildLocationInput(context, weatherProvider),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    elevation: 0,
                    color: Colors.white.withOpacity(0.7),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Použít lokační služby',
                            style: TextStyle(
                              fontSize: 16,
                            ),
                          ),
                      Switch(
                        value: weatherProvider.useGps,
                        activeColor: Colors.pink,
                        inactiveThumbColor: Colors.white,
                        inactiveTrackColor: Colors.grey.withOpacity(0.5),
                        activeTrackColor: Colors.pink.withOpacity(0.5),
                        trackOutlineColor: MaterialStateProperty.all(Colors.transparent),
                        thumbColor: MaterialStateProperty.resolveWith<Color>(
                              (Set<MaterialState> states) {
                            if (states.contains(MaterialState.selected)) {
                              return Colors.white;
                            }
                            return Colors.white;
                          },
                        ),
                        onChanged: (bool value) {
                          weatherProvider.setUseGps(value);
                        },
                      ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    elevation: 0,
                    color: Colors.white.withOpacity(0.7),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Jednotka teploty',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Radio<String>(
                                value: "°C",
                                groupValue: weatherProvider.temperatureUnit,
                                activeColor: Colors.pink,
                                onChanged: (value) {
                                  weatherProvider.setTemperatureUnit(value!);
                                },
                              ),
                              const Text("Celsius (°C)"),
                            ],
                          ),
                          Row(
                            children: [
                              Radio<String>(
                                value: "°F",
                                groupValue: weatherProvider.temperatureUnit,
                                activeColor: Colors.pink,
                                onChanged: (value) {
                                  weatherProvider.setTemperatureUnit(value!);
                                },
                              ),
                              const Text("Fahrenheit (°F)"),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (weatherProvider.errorMessage.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: Text(
                        weatherProvider.errorMessage,
                        style: const TextStyle(
                          color: Colors.red,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  Center(
                    child: Text(
                      'vackoja1',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      onPressed: () => weatherProvider.fetchWeatherData(),
                      child: const Text(
                        'Aktualizovat data',
                        style: TextStyle(color: Colors.pink),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Widget zobrazení a změna aktuální lokality
  Widget _buildLocationInput(BuildContext context, WeatherProvider weatherProvider) {
    final TextEditingController controller = TextEditingController(text: weatherProvider.city);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (weatherProvider.useGps)
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Text(
              'Aktuální město podle GPS: ${weatherProvider.city}',
              style: TextStyle(
                fontStyle: FontStyle.italic,
                color: Colors.black.withOpacity(0.7),
              ),
            ),
          ),
        TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: 'Zadejte město',
            suffixIcon: IconButton(
              icon: const Icon(Icons.search),
              onPressed: () {
                if (controller.text.isNotEmpty) {
                  weatherProvider.setCity(controller.text);
                }
              },
            ),
            enabled: !weatherProvider.useGps,
          ),
          onSubmitted: (value) {
            if (value.isNotEmpty && !weatherProvider.useGps) {
              weatherProvider.setCity(value);
            }
          },
        ),
        if (weatherProvider.useGps)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
          ),
      ],
    );
  }
}