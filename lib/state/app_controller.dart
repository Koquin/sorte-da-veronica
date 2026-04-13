import 'dart:convert';
import 'dart:math';

import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mocks/mock_users.dart';
import '../models/app_user.dart';
import '../models/sale.dart';
import '../models/ticket.dart';

class AppController {
  static const String _ticketsKey = 'tickets_v1';
  static const String _salesKey = 'sales_v1';
  static const String _sessionUserIdKey = 'session_user_id';

  final Random _random = Random();

  SharedPreferences? _prefs;
  List<Ticket> _tickets = <Ticket>[];
  List<Sale> _sales = <Sale>[];
  AppUser? _currentUser;

  AppUser? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;
  bool get isAdmin => _currentUser?.isAdmin == true;

  List<Ticket> get tickets => List<Ticket>.unmodifiable(_tickets);
  List<Sale> get sales => List<Sale>.unmodifiable(_sales);
  List<AppUser> get sellers =>
      mockUsers.where((AppUser user) => !user.isAdmin).toList();

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadTickets();
    await _loadSales();

    final int? userId = _prefs!.getInt(_sessionUserIdKey);
    if (userId != null) {
      _currentUser = mockUsers
          .where((AppUser user) => user.id == userId)
          .firstOrNull;
    }
  }

  Future<bool> login({required String login, required String password}) async {
    final String normalizedLogin = login.trim().toLowerCase();
    final AppUser? user = mockUsers.where((AppUser item) {
      return item.login.toLowerCase() == normalizedLogin &&
          item.password == password;
    }).firstOrNull;

    if (user == null) {
      return false;
    }

    _currentUser = user;
    await _prefs?.setInt(_sessionUserIdKey, user.id);
    return true;
  }

  Future<void> logout() async {
    _currentUser = null;
    await _prefs?.remove(_sessionUserIdKey);
  }

  List<Ticket> searchTickets(String query) {
    final String text = query.trim().toLowerCase();
    if (text.isEmpty) {
      return <Ticket>[];
    }

    final List<Ticket> accessible = _accessibleTicketsForCurrentUser();
    final DateFormat dateFormat = DateFormat('dd/MM/yyyy');

    return accessible.where((Ticket ticket) {
      final String numbersString = ticket.numbers
          .map(_formatNumber)
          .join(' ')
          .toLowerCase();
      final String buyer = (ticket.buyerName ?? '').toLowerCase();
      final String created = dateFormat.format(ticket.createdAt).toLowerCase();
      final String sold = ticket.soldAt == null
          ? ''
          : dateFormat.format(ticket.soldAt!).toLowerCase();

      return numbersString.contains(text) ||
          buyer.contains(text) ||
          created.contains(text) ||
          sold.contains(text);
    }).toList()..sort(
      (Ticket a, Ticket b) => b.createdAt.compareTo(a.createdAt),
    );
  }

  Future<void> generateTickets({required int quantity}) async {
    if (!isAdmin) {
      throw Exception('Apenas administradores podem gerar bilhetes.');
    }
    if (quantity <= 0) {
      throw Exception('Informe uma quantidade valida.');
    }
    if (_tickets.length + quantity > 100) {
      throw Exception('Limite maximo de 100 bilhetes atingido.');
    }

    final Set<int> usedNumbers = <int>{
      for (final Ticket ticket in _tickets) ...ticket.numbers,
    };

    final List<int> availableNumbers = <int>[];
    for (int i = 1; i <= 10000; i++) {
      if (!usedNumbers.contains(i)) {
        availableNumbers.add(i);
      }
    }

    if (availableNumbers.length < quantity * 4) {
      throw Exception('Nao ha numeros suficientes para gerar novos bilhetes.');
    }

    int nextId = _nextTicketId();
    final DateTime now = DateTime.now();

    for (int i = 0; i < quantity; i++) {
      final List<int> numbers = <int>[];
      for (int n = 0; n < 4; n++) {
        final int index = _random.nextInt(availableNumbers.length);
        final int chosen = availableNumbers.removeAt(index);
        numbers.add(chosen);
      }
      numbers.sort();

      _tickets.add(
        Ticket(
          id: nextId,
          numbers: numbers,
          sellerId: null,
          isSold: false,
          soldAt: null,
          createdAt: now,
          assignedBy: null,
          buyerName: null,
        ),
      );
      nextId++;
    }

    await _saveTickets();
  }

  Future<int> assignTicketsByRange({
    required int start,
    required int end,
    required int sellerId,
  }) async {
    if (!isAdmin) {
      throw Exception('Apenas administradores podem atribuir bilhetes.');
    }
    if (start < 1 || end > 10000 || start > end) {
      throw Exception('Intervalo invalido.');
    }

    final int adminId = _currentUser!.id;
    int updated = 0;

    _tickets = _tickets.map((Ticket ticket) {
      final bool shouldAssign = ticket.numbers.any(
        (int number) => number >= start && number <= end,
      );

      if (!shouldAssign) {
        return ticket;
      }

      updated++;
      return ticket.copyWith(sellerId: sellerId, assignedBy: adminId);
    }).toList();

    await _saveTickets();
    return updated;
  }

  Future<int> assignTicketsByNumbers({
    required List<int> numbers,
    required int sellerId,
  }) async {
    if (!isAdmin) {
      throw Exception('Apenas administradores podem atribuir bilhetes.');
    }
    if (numbers.isEmpty) {
      throw Exception('Informe ao menos um numero.');
    }

    final Set<int> set = numbers
        .where((int number) => number >= 1 && number <= 10000)
        .toSet();
    if (set.isEmpty) {
      throw Exception('Numeros invalidos para atribuicao.');
    }

    final int adminId = _currentUser!.id;
    int updated = 0;

    _tickets = _tickets.map((Ticket ticket) {
      final bool shouldAssign = ticket.numbers.any(set.contains);
      if (!shouldAssign) {
        return ticket;
      }
      updated++;
      return ticket.copyWith(sellerId: sellerId, assignedBy: adminId);
    }).toList();

    await _saveTickets();
    return updated;
  }

  Future<void> toggleTicketSold({
    required int ticketId,
    required bool sold,
    String? buyerName,
  }) async {
    final int index = _tickets.indexWhere(
      (Ticket ticket) => ticket.id == ticketId,
    );
    if (index < 0) {
      throw Exception('Bilhete nao encontrado.');
    }

    final Ticket oldTicket = _tickets[index];
    if (!isAdmin) {
      if (oldTicket.sellerId != _currentUser?.id) {
        throw Exception('Voce nao tem permissao para alterar este bilhete.');
      }
    }

    if (sold && oldTicket.sellerId == null) {
      throw Exception('Bilhete sem vendedor atribuido.');
    }

    Ticket updated = oldTicket;
    if (sold) {
      updated = oldTicket.copyWith(
        isSold: true,
        soldAt: DateTime.now(),
        buyerName: (buyerName ?? '').trim().isEmpty ? null : buyerName!.trim(),
      );
    } else {
      updated = oldTicket.copyWith(
        isSold: false,
        clearSoldAt: true,
        clearBuyerName: true,
      );
    }

    _tickets[index] = updated;
    _sales.removeWhere((Sale sale) => sale.ticketId == ticketId);

    if (sold && updated.sellerId != null) {
      _sales.add(
        Sale(
          id: _nextSaleId(),
          ticketId: updated.id,
          value: 2.0,
          sellerId: updated.sellerId!,
          createdAt: DateTime.now(),
        ),
      );
    }

    await _saveTickets();
    await _saveSales();
  }

  List<Ticket> _accessibleTicketsForCurrentUser() {
    if (isAdmin) {
      return _tickets;
    }

    final int? userId = _currentUser?.id;
    if (userId == null) {
      return <Ticket>[];
    }

    return _tickets
        .where((Ticket ticket) => ticket.sellerId == userId)
        .toList();
  }

  String sellerNameById(int id) {
    return mockUsers.where((AppUser user) => user.id == id).firstOrNull?.name ??
        'Desconhecido';
  }

  Map<int, int> soldQuantityBySeller() {
    final Map<int, int> result = <int, int>{};
    for (final Sale sale in _sales) {
      if (!isAdmin && sale.sellerId != _currentUser?.id) {
        continue;
      }
      result[sale.sellerId] = (result[sale.sellerId] ?? 0) + 1;
    }
    return result;
  }

  int soldTotalTickets() {
    if (isAdmin) {
      return _sales.length;
    }

    final int userId = _currentUser!.id;
    return _sales.where((Sale sale) => sale.sellerId == userId).length;
  }

  double soldTotalValue() {
    if (isAdmin) {
      return _sales.fold(0.0, (double sum, Sale sale) => sum + sale.value);
    }

    final int userId = _currentUser!.id;
    return _sales
        .where((Sale sale) => sale.sellerId == userId)
        .fold(0.0, (double sum, Sale sale) => sum + sale.value);
  }

  int _nextTicketId() {
    if (_tickets.isEmpty) {
      return 1;
    }
    return _tickets.map((Ticket ticket) => ticket.id).reduce(max) + 1;
  }

  int _nextSaleId() {
    if (_sales.isEmpty) {
      return 1;
    }
    return _sales.map((Sale sale) => sale.id).reduce(max) + 1;
  }

  Future<void> _loadTickets() async {
    final String? encoded = _prefs?.getString(_ticketsKey);
    if (encoded == null || encoded.isEmpty) {
      _tickets = <Ticket>[];
      return;
    }

    final List<dynamic> raw = jsonDecode(encoded) as List<dynamic>;
    _tickets = raw
        .map((dynamic item) => Ticket.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> _saveTickets() async {
    final String encoded = jsonEncode(
      _tickets.map((Ticket t) => t.toJson()).toList(),
    );
    await _prefs?.setString(_ticketsKey, encoded);
  }

  Future<void> _loadSales() async {
    final String? encoded = _prefs?.getString(_salesKey);
    if (encoded == null || encoded.isEmpty) {
      _sales = <Sale>[];
      return;
    }

    final List<dynamic> raw = jsonDecode(encoded) as List<dynamic>;
    _sales = raw
        .map((dynamic item) => Sale.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> _saveSales() async {
    final String encoded = jsonEncode(
      _sales.map((Sale s) => s.toJson()).toList(),
    );
    await _prefs?.setString(_salesKey, encoded);
  }

  String formatNumber(int number) => _formatNumber(number);

  String _formatNumber(int number) {
    return number.toString().padLeft(4, '0');
  }
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull {
    if (isEmpty) {
      return null;
    }
    return first;
  }
}
