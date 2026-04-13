import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../models/ticket.dart';
import '../repositories/lottery_repository.dart';

class AppViewModel extends ChangeNotifier {
  AppViewModel(this._repository);

  final LotteryRepository _repository;

  bool _initialized = false;
  bool _isBusy = false;
  String? _errorMessage;
  int _currentTab = 0;
  bool _hasSearched = false;
  String _lastQuery = '';
  List<Ticket> _searchedTickets = <Ticket>[];

  bool get initialized => _initialized;
  bool get isBusy => _isBusy;
  String? get errorMessage => _errorMessage;
  int get currentTab => _currentTab;
  bool get hasSearched => _hasSearched;
  List<Ticket> get searchedTickets =>
      List<Ticket>.unmodifiable(_searchedTickets);

  AppUser? get currentUser => _repository.currentUser;
  bool get isLoggedIn => _repository.currentUser != null;
  bool get isAdmin => _repository.isAdmin;
  List<AppUser> get sellers => _repository.sellers;

  int get totalTickets => _repository.tickets.length;
  int get soldTotalTickets => _repository.soldTotalTickets();
  double get soldTotalValue => _repository.soldTotalValue();

  Map<int, int> get soldBySeller => _repository.soldQuantityBySeller();

  String sellerNameById(int id) => _repository.sellerNameById(id);
  String formatNumber(int number) => _repository.formatNumber(number);

  Future<void> init() async {
    _setBusy(true);
    _clearError();
    try {
      await _repository.init();
      _initialized = true;
      _searchedTickets = _repository.searchTickets('');
      _hasSearched = true;
    } catch (e) {
      _setError('Falha ao inicializar: $e');
    }
    _setBusy(false);
    notifyListeners();
  }

  Future<bool> login(String login, String password) async {
    _setBusy(true);
    _clearError();
    notifyListeners();

    try {
      final bool success = await _repository.login(
        login: login,
        password: password,
      );
      if (!success) {
        _setError('Login ou senha invalidos.');
      }
      _setBusy(false);
      notifyListeners();
      return success;
    } catch (e) {
      _setBusy(false);
      _setError('Erro ao autenticar: $e');
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    _setBusy(true);
    _clearError();
    notifyListeners();

    try {
      await _repository.logout();
      _currentTab = 0;
      _hasSearched = false;
      _searchedTickets = <Ticket>[];
    } catch (e) {
      _setError('Erro ao sair: $e');
    }

    _setBusy(false);
    notifyListeners();
  }

  void setTab(int index) {
    _currentTab = index;
    notifyListeners();

    if (index == 2) {
      refreshStats();
    }
  }

  Future<void> refreshStats() async {
    try {
      await _repository.refreshLocalData();
      notifyListeners();
    } catch (e) {
      _setError('Falha ao atualizar estatisticas: $e');
      notifyListeners();
    }
  }

  void searchTickets(String query) {
    _clearError();
    _lastQuery = query;
    _searchedTickets = _repository.searchTickets(query);
    _hasSearched = query.trim().isNotEmpty;
    notifyListeners();
  }

  Future<bool> generateTickets(int quantity) async {
    return _runAction(() async {
      await _repository.generateTickets(quantity: quantity);
    });
  }

  Future<int?> assignByRange({
    required int start,
    required int end,
    required int sellerId,
  }) async {
    int? updated;
    final bool success = await _runAction(() async {
      updated = await _repository.assignTicketsByRange(
        start: start,
        end: end,
        sellerId: sellerId,
      );
    });
    return success ? updated : null;
  }

  Future<int?> assignByNumbers({
    required List<int> numbers,
    required int sellerId,
  }) async {
    int? updated;
    final bool success = await _runAction(() async {
      updated = await _repository.assignTicketsByNumbers(
        numbers: numbers,
        sellerId: sellerId,
      );
    });
    return success ? updated : null;
  }

  Future<bool> toggleTicketSold({
    required int ticketId,
    required bool sold,
    String? buyerName,
  }) async {
    return _runAction(() async {
      await _repository.toggleTicketSold(
        ticketId: ticketId,
        sold: sold,
        buyerName: buyerName,
      );

      if (_hasSearched) {
        _searchedTickets = _repository.searchTickets(_lastQuery);
      }
    });
  }

  Future<bool> _runAction(Future<void> Function() action) async {
    _setBusy(true);
    _clearError();
    notifyListeners();
    try {
      await action();
      if (_currentTab == 2) {
        await _repository.refreshLocalData();
      }
      _setBusy(false);
      notifyListeners();
      return true;
    } catch (e) {
      _setBusy(false);
      _setError(e.toString().replaceFirst('Exception: ', ''));
      notifyListeners();
      return false;
    }
  }

  void _setBusy(bool value) {
    _isBusy = value;
  }

  void _setError(String message) {
    _errorMessage = message;
  }

  void _clearError() {
    _errorMessage = null;
  }
}
