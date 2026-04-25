// ignore_for_file: avoid_print

import 'package:flutter/material.dart';

import '../viewmodels/app_view_model.dart';

void _log(String method, String message) {
  print('In LoginView, Method: $method, $message');
}

class LoginView extends StatefulWidget {
  const LoginView({super.key, required this.viewModel});

  final AppViewModel viewModel;

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final TextEditingController _loginController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void dispose() {
    _log('dispose', 'Disposing login controllers');
    _loginController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    _log('_submit', 'Submitting login for user "${_loginController.text}"');
    final bool success = await widget.viewModel.login(
      _loginController.text,
      _passwordController.text,
    );

    if (!mounted) {
      _log('_submit', 'Widget unmounted before handling result, returning');
      return;
    }

    if (!success) {
      final String message =
          widget.viewModel.errorMessage == 'Login ou senha invalidos.'
          ? 'Dados incorretos'
          : 'Erro ao fazer login';
      _log('_submit', 'Login failed. Showing message="$message"');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    _log('_submit', 'Login success');
  }

  @override
  Widget build(BuildContext context) {
    _log('build', 'Building LoginView');
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[Color(0xFFDDF8DE), Color(0xFFFFFFFF)],
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              elevation: 3,
              margin: const EdgeInsets.all(20),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      'Sorte da Veronica',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _loginController,
                      decoration: const InputDecoration(
                        labelText: 'Login',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Senha',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Admin padrao: V3R0N1C4 / V3R0N1C4',
                      style: TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: widget.viewModel.isBusy ? null : _submit,
                        child: const Text('Entrar'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
