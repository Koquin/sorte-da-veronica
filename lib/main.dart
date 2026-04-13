import 'package:flutter/material.dart';

import 'repositories/lottery_repository.dart';
import 'viewmodels/app_view_model.dart';
import 'views/home_view.dart';
import 'views/login_view.dart';

void main() {
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
    _viewModel = AppViewModel(LotteryRepository());
    _viewModel.init();
  }

  @override
  Widget build(BuildContext context) {
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
    if (!_viewModel.initialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_viewModel.isLoggedIn) {
      return LoginView(viewModel: _viewModel);
    }

    return HomeView(viewModel: _viewModel);
  }
}
