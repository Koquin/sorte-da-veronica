// ignore_for_file: avoid_print

import 'package:flutter/material.dart';

import '../models/app_city.dart';
import '../models/app_user.dart';
import '../models/ticket.dart';
import '../repositories/lottery_repository.dart';

void _log(String method, String message) {
  print('In AppViewModel, Method: $method, $message');
}

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
  List<AppCity> get cities => _repository.cities;
  int? get currentCityId => _repository.currentCityId;

  int get totalTickets => _repository.tickets.length;
  int get soldTotalTickets => _repository.soldTotalTickets();
  double get soldTotalValue => _repository.soldTotalValue();

  Map<int, int> get soldBySeller => _repository.soldQuantityBySeller();
  Map<String, int> get soldByClient => _repository.soldQuantityByBuyer();

  String sellerNameById(int id) => _repository.sellerNameById(id);
  String? sellerContactById(int id) => _repository.sellerContactById(id);
  String formatNumber(int number) => _repository.formatNumber(number);

  String _stateSummary() {
    return 'state={initialized:$_initialized, isBusy:$_isBusy, currentTab:$_currentTab, '
        'hasSearched:$_hasSearched, lastQuery:"$_lastQuery", results:${_searchedTickets.length}, '
        'isLoggedIn:$isLoggedIn, isAdmin:$isAdmin, userId:${currentUser?.id}, cityId:$currentCityId}';
  }

  Future<void> init() async {
    _log('init', 'Starting ViewModel initialization | ${_stateSummary()}');
    _setBusy(true);
    _clearError();
    try {
      await _repository.init();
      _initialized = true;
      _searchedTickets = _repository.searchTickets('');
      _hasSearched = true;
    } catch (e, s) {
      await _reportError(operation: 'init', error: e, stackTrace: s);
      _setError('Falha ao inicializar: $e');
    }
    _setBusy(false);
    _log(
      'init',
      'Initialization completed. initialized=$_initialized searchedTickets=${_searchedTickets.length} | ${_stateSummary()}',
    );
    notifyListeners();
  }

  Future<bool> login(String login, String password) async {
    _log('login', 'Attempting login for user "$login" | ${_stateSummary()}');
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
      _log('login', 'Return: $success | ${_stateSummary()}');
      notifyListeners();
      return success;
    } catch (e, s) {
      await _reportError(
        operation: 'login',
        error: e,
        stackTrace: s,
        payload: <String, dynamic>{'login': login},
      );
      _setBusy(false);
      _setError('Erro ao autenticar: $e');
      _log('login', 'Return: false (exception=$e) | ${_stateSummary()}');
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    _log('logout', 'Starting logout | ${_stateSummary()}');
    _setBusy(true);
    _clearError();
    notifyListeners();

    try {
      await _repository.logout();
      _currentTab = 0;
      _hasSearched = false;
      _searchedTickets = <Ticket>[];
    } catch (e, s) {
      await _reportError(operation: 'logout', error: e, stackTrace: s);
      _setError('Erro ao sair: $e');
    }

    _setBusy(false);
    _log('logout', 'Logout completed | ${_stateSummary()}');
    notifyListeners();
  }

  void setTab(int index) {
    _log(
      'setTab',
      'Changing tab from $_currentTab to $index | ${_stateSummary()}',
    );
    _currentTab = index;
    notifyListeners();

    if (index == 2) {
      refreshStats();
    }
  }

  Future<void> refreshStats() async {
    _log(
      'refreshStats',
      'Refreshing stats from repository | ${_stateSummary()}',
    );
    try {
      await _repository.refreshLocalData();
      _log('refreshStats', 'Stats refresh completed | ${_stateSummary()}');
      notifyListeners();
    } catch (e, s) {
      await _reportError(operation: 'refreshStats', error: e, stackTrace: s);
      _setError('Falha ao atualizar estatisticas: $e');
      _log('refreshStats', 'Stats refresh failed: $e | ${_stateSummary()}');
      notifyListeners();
    }
  }

  Future<bool> switchCity(int cityId) async {
    _log('switchCity', 'Switching active city to $cityId | ${_stateSummary()}');
    return _runAction(() async {
      await _repository.switchCity(cityId);
      _searchedTickets = _repository.searchTickets(_lastQuery);
      _hasSearched = true;
    });
  }

  void searchTickets(String query) {
    _log(
      'searchTickets',
      'Searching tickets with query="$query" | ${_stateSummary()}',
    );
    _clearError();
    _lastQuery = query;
    _searchedTickets = _repository.searchTickets(query);
    _hasSearched = query.trim().isNotEmpty;
    _log(
      'searchTickets',
      'Search completed with ${_searchedTickets.length} result(s) | ${_stateSummary()}',
    );
    notifyListeners();
  }

  Future<bool> generateTickets(int quantity) async {
    _log(
      'generateTickets',
      'Generating $quantity ticket(s) | ${_stateSummary()}',
    );

    return _runAction(() async {
      await _repository.generateTickets(quantity: quantity);
    });
  }

  Future<bool> createCity(String name) async {
    _log('createCity', 'Creating city "$name" | ${_stateSummary()}');
    return _runAction(() async {
      await _repository.createCity(cityName: name);
    });
  }

  Future<bool> createSeller({
    required String userName,
    required String userContact,
    required String login,
    required String password,
  }) async {
    _log(
      'createSeller',
      'Creating seller login="$login" userName="$userName" | ${_stateSummary()}',
    );
    return _runAction(() async {
      await _repository.createSeller(
        userName: userName,
        userContact: userContact,
        login: login,
        password: password,
      );
    });
  }

  Future<bool> updateSeller({
    required int sellerId,
    required String userName,
    required String userContact,
    required String login,
    String? password,
  }) async {
    _log(
      'updateSeller',
      'Updating sellerId=$sellerId login="$login" userName="$userName" | ${_stateSummary()}',
    );
    return _runAction(() async {
      await _repository.updateSeller(
        sellerId: sellerId,
        userName: userName,
        userContact: userContact,
        login: login,
        password: password,
      );
    });
  }

  Future<bool> deleteSeller(int sellerId) async {
    _log('deleteSeller', 'Deleting sellerId=$sellerId | ${_stateSummary()}');
    bool deleted = false;
    final bool success = await _runAction(() async {
      deleted = await _repository.deleteSeller(sellerId: sellerId);
    });
    if (!success) {
      return false;
    }
    if (!deleted) {
      _setError('Vendedor nao encontrado para exclusao.');
      notifyListeners();
      return false;
    }
    return true;
  }

  Future<int?> assignByRange({
    required int start,
    required int end,
    required int sellerId,
  }) async {
    _log(
      'assignByRange',
      'Assigning by range start=$start end=$end sellerId=$sellerId | ${_stateSummary()}',
    );
    int? updated;
    final bool success = await _runAction(() async {
      updated = await _repository.assignTicketsByRange(
        start: start,
        end: end,
        sellerId: sellerId,
      );
    });
    final int? result = success ? updated : null;
    _log('assignByRange', 'Return: ${result ?? 'null'} | ${_stateSummary()}');
    return result;
  }

  Future<int?> assignByNumbers({
    required List<int> numbers,
    required int sellerId,
  }) async {
    _log(
      'assignByNumbers',
      'Assigning by numbers count=${numbers.length} sellerId=$sellerId numbers=$numbers | ${_stateSummary()}',
    );
    int? updated;
    final bool success = await _runAction(() async {
      updated = await _repository.assignTicketsByNumbers(
        numbers: numbers,
        sellerId: sellerId,
      );
    });
    final int? result = success ? updated : null;
    _log('assignByNumbers', 'Return: ${result ?? 'null'} | ${_stateSummary()}');
    return result;
  }

  Future<bool> toggleTicketSold({
    required int ticketId,
    required bool sold,
    String? buyerName,
    String? buyerContact,
  }) async {
    _log(
      'toggleTicketSold',
      'Toggling ticketId=$ticketId sold=$sold buyerName=${buyerName ?? ''} buyerContact=${buyerContact ?? ''} | ${_stateSummary()}',
    );
    return _runAction(() async {
      await _repository.toggleTicketSold(
        ticketId: ticketId,
        sold: sold,
        buyerName: buyerName,
        buyerContact: buyerContact,
      );

      _searchedTickets = _repository.searchTickets(_lastQuery);
    });
  }

  Future<bool> deleteTicketById(int ticketId) async {
    _log(
      'deleteTicketById',
      'Deleting ticketId=$ticketId | ${_stateSummary()}',
    );
    bool deleted = false;
    final bool success = await _runAction(() async {
      deleted = await _repository.deleteTicketById(ticketId: ticketId);
      _searchedTickets = _repository.searchTickets(_lastQuery);
    });
    if (!success) {
      return false;
    }
    if (!deleted) {
      _setError('Bilhete nao encontrado para exclusao.');
      notifyListeners();
      return false;
    }
    return true;
  }

  Future<bool> deleteTicketByNumber(int number) async {
    _log(
      'deleteTicketByNumber',
      'Deleting by number=$number | ${_stateSummary()}',
    );
    bool deleted = false;
    final bool success = await _runAction(() async {
      deleted = await _repository.deleteTicketByNumber(number: number);
      _searchedTickets = _repository.searchTickets(_lastQuery);
    });
    if (!success) {
      return false;
    }
    if (!deleted) {
      _setError('Bilhete nao encontrado para exclusao.');
      notifyListeners();
      return false;
    }
    return true;
  }

  Future<int?> deleteTicketsByRange({
    required int start,
    required int end,
  }) async {
    _log(
      'deleteTicketsByRange',
      'Deleting tickets by range start=$start end=$end | ${_stateSummary()}',
    );
    int? deleted;
    final bool success = await _runAction(() async {
      deleted = await _repository.deleteTicketsByRange(start: start, end: end);
      _searchedTickets = _repository.searchTickets(_lastQuery);
    });
    return success ? deleted : null;
  }

  Future<bool> updateTicketNumbers({
    required int ticketId,
    required List<int> numbers,
  }) async {
    _log(
      'updateTicketNumbers',
      'Updating ticketId=$ticketId numbers=$numbers | ${_stateSummary()}',
    );
    return _runAction(() async {
      await _repository.updateTicketNumbers(
        ticketId: ticketId,
        numbers: numbers,
      );
      _searchedTickets = _repository.searchTickets(_lastQuery);
    });
  }

  Future<bool> _runAction(Future<void> Function() action) async {
    _log('_runAction', 'Starting wrapped action | ${_stateSummary()}');
    _setBusy(true);
    _clearError();
    notifyListeners();
    try {
      await action();
      if (_currentTab == 2) {
        await _repository.refreshLocalData();
      }
      _setBusy(false);
      _log('_runAction', 'Return: true | ${_stateSummary()}');
      notifyListeners();
      return true;
    } catch (e, s) {
      await _reportError(operation: '_runAction', error: e, stackTrace: s);
      _setBusy(false);
      _setError(e.toString().replaceFirst('Exception: ', ''));
      _log('_runAction', 'Return: false (exception=$e) | ${_stateSummary()}');
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

  Future<void> _reportError({
    required String operation,
    required Object error,
    StackTrace? stackTrace,
    Map<String, dynamic>? payload,
  }) async {
    await _repository.logError(
      source: 'AppViewModel',
      operation: operation,
      message: error.toString(),
      stackTrace: stackTrace?.toString(),
      payload: payload,
    );
  }
}
