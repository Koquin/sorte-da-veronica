// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'repositories/lottery_repository.dart';
import 'viewmodels/app_view_model.dart';
import 'views/home_view.dart';
import 'views/login_view.dart';

void _log(String method, String message) {
  print('In MainApp, Method: $method, $message');
}

Future<void> main() async {
  _log('main', 'Starting app bootstrap');
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL'] ?? '',
    anonKey: dotenv.env['SUPABASE_ANON_KEY'] ?? '',
  );

  _log('main', 'Supabase initialized, running app');
  runApp(const SorteDaVeronicaApp());
}

class SorteDaVeronicaApp extends StatefulWidget {
  const SorteDaVeronicaApp({super.key});

  @override
  State<SorteDaVeronicaApp> createState() => _SorteDaVeronicaAppState();
}

class _SorteDaVeronicaAppState extends State<SorteDaVeronicaApp> {
  late final AppViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _log('_SorteDaVeronicaAppState.initState', 'Creating ViewModel');
    _viewModel = AppViewModel(LotteryRepository());
    _viewModel.init();
  }

  @override
  Widget build(BuildContext context) {
    _log('_SorteDaVeronicaAppState.build', 'Building root MaterialApp');
    return AnimatedBuilder(
      animation: _viewModel,
      builder: (BuildContext context, _) {
        return MaterialApp(
          title: 'Sorte da Veronica',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF6EC177),
              brightness: Brightness.light,
            ),
            scaffoldBackgroundColor: const Color(0xFFEDF9EE),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFFE2F8E4),
              foregroundColor: Color(0xFF1F4D25),
            ),
            useMaterial3: true,
          ),
          home: _buildHome(),
        );
      },
    );
  }

  Widget _buildHome() {
    _log('_SorteDaVeronicaAppState._buildHome', 'Deciding initial route');
    if (!_viewModel.initialized) {
      _log('_SorteDaVeronicaAppState._buildHome', 'Showing loading screen');
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_viewModel.isLoggedIn) {
      _log('_SorteDaVeronicaAppState._buildHome', 'Showing LoginView');
      return LoginView(viewModel: _viewModel);
    }

    _log('_SorteDaVeronicaAppState._buildHome', 'Showing HomeView');
    return HomeView(viewModel: _viewModel);
  }
}
