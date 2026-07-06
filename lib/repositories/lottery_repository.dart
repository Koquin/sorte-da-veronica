// ignore_for_file: avoid_print

import 'package:bcrypt/bcrypt.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_city.dart';
import '../models/app_user.dart';
import '../models/sale.dart';
import '../models/ticket.dart';

void _log(String method, String message) {
  print('In LotteryRepository, Method: $method, $message');
}

class LotteryRepository {
  static const String _sessionTokenKey = 'session_token';
  static const String _sessionExpiresAtKey = 'session_expires_at';

  SharedPreferences? _prefs;

  String? _sessionToken;

  List<Ticket> _tickets = <Ticket>[];
  List<Sale> _sales = <Sale>[];
  List<AppUser> _sellers = <AppUser>[];
  List<AppCity> _cities = <AppCity>[];
  AppUser? _currentUser;
  int? _currentCityId;

  AppUser? get currentUser => _currentUser;
  List<Ticket> get tickets => List<Ticket>.unmodifiable(_tickets);
  List<Sale> get sales => List<Sale>.unmodifiable(_sales);
  List<AppUser> get sellers => List<AppUser>.unmodifiable(_sellers);
  List<AppCity> get cities => List<AppCity>.unmodifiable(_cities);
  int? get currentCityId => _currentCityId;

  bool get isAdmin => _currentUser?.isAdmin == true;

  SupabaseClient get _client => Supabase.instance.client;

  String _stateSummary() {
    return 'state={userId:${_currentUser?.id}, isAdmin:$isAdmin, cityId:$_currentCityId, '
        'tickets:${_tickets.length}, sales:${_sales.length}, sellers:${_sellers.length}, '
        'cities:${_cities.length}, hasToken:${_sessionToken != null}}';
  }

  Future<void> init() async {
    _log('init', 'Starting repository initialization | ${_stateSummary()}');
    _prefs = await SharedPreferences.getInstance();

    final String? token = _prefs?.getString(_sessionTokenKey);
    final String? expiresText = _prefs?.getString(_sessionExpiresAtKey);

    if (token == null || expiresText == null) {
      _log(
        'init',
        'No persisted session found, returning without login | ${_stateSummary()}',
      );
      return;
    }

    final DateTime? expiresAt = DateTime.tryParse(expiresText);
    if (expiresAt == null || DateTime.now().isAfter(expiresAt)) {
      _log(
        'init',
        'Session expired or invalid, clearing session | expiresText=$expiresText',
      );
      await _clearSession();
      return;
    }

    _sessionToken = token;

    final bool valid = await _validateSessionAndBootstrap();
    if (!valid) {
      _log(
        'init',
        'Persisted session invalid on backend, clearing local session',
      );
      await _clearSession();
      return;
    }

    _log(
      'init',
      'Repository initialized with active session | ${_stateSummary()}',
    );
  }

  Future<bool> login({required String login, required String password}) async {
    _log('login', 'Attempting login for user "$login" | ${_stateSummary()}');
    final dynamic loginPayloadRaw = await _client.rpc(
      'app_get_login_payload',
      params: <String, dynamic>{'p_login': login.trim()},
    );

    if (loginPayloadRaw == null) {
      _log('login', 'Return: false (invalid credentials: login not found)');
      return false;
    }

    final Map<String, dynamic> payload = Map<String, dynamic>.from(
      loginPayloadRaw as Map,
    );
    final String? passwordHash = payload['password_hash'] as String?;
    final int? cityId = payload['city_id'] as int?;
    final Map<String, dynamic>? userJson = payload['user'] == null
        ? null
        : Map<String, dynamic>.from(payload['user'] as Map);

    if (passwordHash == null || cityId == null || userJson == null) {
      throw StateError(
        'Payload de login invalido retornado pelo backend (campos ausentes).',
      );
    }

    final bool passwordOk;
    try {
      passwordOk = BCrypt.checkpw(password, passwordHash);
    } catch (e) {
      throw StateError('Falha ao validar senha localmente: $e');
    }

    if (!passwordOk) {
      _log('login', 'Return: false (invalid credentials from app-side check)');
      return false;
    }

    final dynamic sessionRaw = await _client.rpc(
      'app_create_session',
      params: <String, dynamic>{
        'p_user_id': userJson['id'],
        'p_city_id': cityId,
      },
    );

    if (sessionRaw == null) {
      throw StateError('app_create_session retornou nulo.');
    }

    final Map<String, dynamic> session = Map<String, dynamic>.from(
      sessionRaw as Map,
    );
    final String? token = session['token'] as String?;
    final String? expiresAtText = session['expires_at'] as String?;

    if (token == null || expiresAtText == null) {
      throw StateError(
        'Resposta invalida de app_create_session (token/expiracao ausentes).',
      );
    }

    final DateTime? expiresAt = DateTime.tryParse(expiresAtText);
    if (expiresAt == null) {
      throw StateError('Data de expiracao da sessao invalida: $expiresAtText');
    }

    _sessionToken = token;

    await _prefs?.setString(_sessionTokenKey, token);
    await _prefs?.setString(_sessionExpiresAtKey, expiresAt.toIso8601String());

    _applyAuthPayload(session);
    await _bootstrap();
    _log(
      'login',
      'Return: true (login success) | expiresAt=$expiresAt | ${_stateSummary()}',
    );
    return true;
  }

  Future<void> logout() async {
    _log('logout', 'Starting logout | ${_stateSummary()}');
    final String? token = _sessionToken;
    if (token != null) {
      try {
        await _client.rpc(
          'app_logout',
          params: <String, dynamic>{'p_token': token},
        );
      } catch (_) {
        // Ignore logout errors and clear local session anyway.
      }
    }

    await _clearSession();
    _currentUser = null;
    _currentCityId = null;
    _tickets = <Ticket>[];
    _sales = <Sale>[];
    _sellers = <AppUser>[];
    _cities = <AppCity>[];
    _log(
      'logout',
      'Logout finished and local state cleaned | ${_stateSummary()}',
    );
  }

  Future<void> switchCity(int cityId) async {
    _log('switchCity', 'Switching to cityId=$cityId | ${_stateSummary()}');
    final String token = _requireToken();

    await _client.rpc(
      'app_switch_city',
      params: <String, dynamic>{'p_token': token, 'p_city_id': cityId},
    );

    _currentCityId = cityId;
    await _bootstrap();
    _log('switchCity', 'City switched successfully | ${_stateSummary()}');
  }

  Future<void> refreshLocalData() async {
    _log(
      'refreshLocalData',
      'Refreshing local cache from backend | ${_stateSummary()}',
    );
    if (_sessionToken == null) {
      _log(
        'refreshLocalData',
        'No session token found, returning without refresh',
      );
      return;
    }
    await _bootstrap();
    _log('refreshLocalData', 'Refresh completed | ${_stateSummary()}');
  }

  List<Ticket> searchTickets(String query) {
    _log(
      'searchTickets',
      'Filtering tickets with query="$query" | totalTickets=${_tickets.length}',
    );
    final String text = query.trim().toLowerCase();
    if (text.isEmpty) {
      final List<Ticket> all = _tickets.toList()
        ..sort((Ticket a, Ticket b) => a.id.compareTo(b.id));
      _log(
        'searchTickets',
        'Return: ${all.length} ticket(s) for empty query | ${_stateSummary()}',
      );
      return all;
    }

    final DateFormat dateFormat = DateFormat('dd/MM/yyyy');

    final List<Ticket> filtered = _tickets.where((Ticket ticket) {
      final String numbersString = ticket.numbers
          .map(formatNumber)
          .join(' ')
          .toLowerCase();
      final String buyer = (ticket.buyerName ?? '').toLowerCase();
      final String seller = ticket.sellerId == null
          ? ''
          : sellerNameById(ticket.sellerId!).toLowerCase();
      final String created = dateFormat.format(ticket.createdAt).toLowerCase();
      final String sold = ticket.soldAt == null
          ? ''
          : dateFormat.format(ticket.soldAt!).toLowerCase();

      return numbersString.contains(text) ||
          buyer.contains(text) ||
          seller.contains(text) ||
          created.contains(text) ||
          sold.contains(text);
    }).toList();

    filtered.sort((Ticket a, Ticket b) => b.createdAt.compareTo(a.createdAt));
    _log(
      'searchTickets',
      'Return: ${filtered.length} filtered ticket(s) | query="$query"',
    );
    return filtered;
  }

  Future<void> generateTickets({required int quantity}) async {
    _log(
      'generateTickets',
      'Generating quantity=$quantity | ${_stateSummary()}',
    );
    final String token = _requireToken();

    await _client.rpc(
      'app_generate_tickets',
      params: <String, dynamic>{'p_token': token, 'p_quantity': quantity},
    );

    await _bootstrap();
    _log('generateTickets', 'Generation completed | ${_stateSummary()}');
  }

  Future<void> createCity({required String cityName}) async {
    _log('createCity', 'Creating city "$cityName" | ${_stateSummary()}');
    final String token = _requireToken();

    await _client.rpc(
      'app_create_city',
      params: <String, dynamic>{'p_token': token, 'p_name': cityName},
    );

    await _bootstrap();
    _log('createCity', 'City created successfully | ${_stateSummary()}');
  }

  Future<void> createSeller({
    required String userName,
    required String userContact,
    required String login,
    required String password,
  }) async {
    _log(
      'createSeller',
      'Creating seller login="$login" name="$userName" | ${_stateSummary()}',
    );
    final String token = _requireToken();

    final String passwordHash = BCrypt.hashpw(password, BCrypt.gensalt());

    await _client.rpc(
      'app_create_seller',
      params: <String, dynamic>{
        'p_token': token,
        'p_user_name': userName,
        'p_user_contact': userContact,
        'p_login': login,
        'p_password_hash': passwordHash,
      },
    );

    await _bootstrap();
    _log('createSeller', 'Seller created successfully | ${_stateSummary()}');
  }

  Future<void> updateSeller({
    required int sellerId,
    required String userName,
    required String userContact,
    required String login,
    String? password,
  }) async {
    _log(
      'updateSeller',
      'Updating sellerId=$sellerId login="$login" name="$userName" | ${_stateSummary()}',
    );
    final String token = _requireToken();

    final String? passwordHash = (password == null || password.trim().isEmpty)
        ? null
        : BCrypt.hashpw(password, BCrypt.gensalt());

    await _client.rpc(
      'app_update_seller',
      params: <String, dynamic>{
        'p_token': token,
        'p_seller_id': sellerId,
        'p_user_name': userName,
        'p_user_contact': userContact,
        'p_login': login,
        'p_password_hash': passwordHash,
      },
    );

    await _bootstrap();
    _log('updateSeller', 'Seller updated successfully | ${_stateSummary()}');
  }

  Future<bool> deleteSeller({required int sellerId}) async {
    _log('deleteSeller', 'Deleting sellerId=$sellerId | ${_stateSummary()}');
    final String token = _requireToken();

    final dynamic result = await _client.rpc(
      'app_delete_seller',
      params: <String, dynamic>{'p_token': token, 'p_seller_id': sellerId},
    );

    await _bootstrap();
    final bool deleted = result == true;
    _log('deleteSeller', 'Return: $deleted | ${_stateSummary()}');
    return deleted;
  }

  Future<int> assignTicketsByRange({
    required int start,
    required int end,
    required int sellerId,
  }) async {
    _log(
      'assignTicketsByRange',
      'Assign by range start=$start end=$end sellerId=$sellerId | ${_stateSummary()}',
    );
    final String token = _requireToken();

    final dynamic result = await _client.rpc(
      'app_assign_tickets_by_range',
      params: <String, dynamic>{
        'p_token': token,
        'p_start': start,
        'p_end': end,
        'p_seller_id': sellerId,
      },
    );

    await _bootstrap();
    final int updated = (result as num?)?.toInt() ?? 0;
    _log(
      'assignTicketsByRange',
      'Return: updated=$updated | ${_stateSummary()}',
    );
    return updated;
  }

  Future<int> assignTicketsByNumbers({
    required List<int> numbers,
    required int sellerId,
  }) async {
    _log(
      'assignTicketsByNumbers',
      'Assign by numbers count=${numbers.length} sellerId=$sellerId numbers=$numbers | ${_stateSummary()}',
    );
    final String token = _requireToken();

    final dynamic result = await _client.rpc(
      'app_assign_tickets_by_numbers',
      params: <String, dynamic>{
        'p_token': token,
        'p_numbers': numbers,
        'p_seller_id': sellerId,
      },
    );

    await _bootstrap();
    final int updated = (result as num?)?.toInt() ?? 0;
    _log(
      'assignTicketsByNumbers',
      'Return: updated=$updated | ${_stateSummary()}',
    );
    return updated;
  }

  Future<int> assignTicketsByQuantity({
    required int quantity,
    required int sellerId,
  }) async {
    _log(
      'assignTicketsByQuantity',
      'Assign by quantity=$quantity sellerId=$sellerId | ${_stateSummary()}',
    );
    final String token = _requireToken();

    final dynamic result = await _client.rpc(
      'app_assign_tickets_by_quantity',
      params: <String, dynamic>{
        'p_token': token,
        'p_quantity': quantity,
        'p_seller_id': sellerId,
      },
    );

    await _bootstrap();
    final int updated = (result as num?)?.toInt() ?? 0;
    _log(
      'assignTicketsByQuantity',
      'Return: updated=$updated | ${_stateSummary()}',
    );
    return updated;
  }

  Future<void> toggleTicketSold({
    required int ticketId,
    required bool sold,
    String? buyerName,
    String? buyerContact,
  }) async {
    _log(
      'toggleTicketSold',
      'Updating ticketId=$ticketId sold=$sold buyerName=${buyerName ?? ''} buyerContact=${buyerContact ?? ''} | ${_stateSummary()}',
    );
    final String token = _requireToken();

    await _client.rpc(
      'app_toggle_ticket_sold',
      params: <String, dynamic>{
        'p_token': token,
        'p_ticket_id': ticketId,
        'p_is_sold': sold,
        'p_buyer_name': buyerName,
        'p_buyer_contact': buyerContact,
      },
    );

    await _bootstrap();
    _log(
      'toggleTicketSold',
      'Ticket sale status updated successfully | ${_stateSummary()}',
    );
  }

  Future<bool> deleteTicketById({required int ticketId}) async {
    _log(
      'deleteTicketById',
      'Deleting ticketId=$ticketId | ${_stateSummary()}',
    );
    final String token = _requireToken();

    final dynamic result = await _client.rpc(
      'app_delete_ticket_by_id',
      params: <String, dynamic>{'p_token': token, 'p_ticket_id': ticketId},
    );

    await _bootstrap();
    final bool deleted = result == true;
    _log('deleteTicketById', 'Return: $deleted | ${_stateSummary()}');
    return deleted;
  }

  Future<bool> deleteTicketByNumber({required int number}) async {
    _log(
      'deleteTicketByNumber',
      'Deleting by number=$number | ${_stateSummary()}',
    );
    final String token = _requireToken();

    final dynamic result = await _client.rpc(
      'app_delete_ticket_by_number',
      params: <String, dynamic>{'p_token': token, 'p_number': number},
    );

    await _bootstrap();
    final bool deleted = result == true;
    _log('deleteTicketByNumber', 'Return: $deleted | ${_stateSummary()}');
    return deleted;
  }

  Future<int> deleteTicketsByRange({
    required int start,
    required int end,
  }) async {
    _log(
      'deleteTicketsByRange',
      'Deleting tickets by range start=$start end=$end | ${_stateSummary()}',
    );
    final String token = _requireToken();

    final dynamic result = await _client.rpc(
      'app_delete_tickets_by_range',
      params: <String, dynamic>{
        'p_token': token,
        'p_start': start,
        'p_end': end,
      },
    );

    await _bootstrap();
    final int deleted = (result as num?)?.toInt() ?? 0;
    _log('deleteTicketsByRange', 'Return: $deleted | ${_stateSummary()}');
    return deleted;
  }

  Future<void> updateTicketNumbers({
    required int ticketId,
    required List<int> numbers,
  }) async {
    _log(
      'updateTicketNumbers',
      'Updating ticketId=$ticketId with numbers=$numbers | ${_stateSummary()}',
    );
    final String token = _requireToken();

    await _client.rpc(
      'app_update_ticket_numbers',
      params: <String, dynamic>{
        'p_token': token,
        'p_ticket_id': ticketId,
        'p_numbers': numbers,
      },
    );

    await _bootstrap();
    _log(
      'updateTicketNumbers',
      'Ticket updated successfully | ${_stateSummary()}',
    );
  }

  String sellerNameById(int id) {
    _log('sellerNameById', 'Resolving seller name for id=$id');
    if (_currentUser?.id == id) {
      final String name = _currentUser?.name ?? 'Desconhecido';
      _log('sellerNameById', 'Return: $name (current user)');
      return name;
    }

    final AppUser? seller = _sellers
        .where((AppUser u) => u.id == id)
        .firstOrNull;
    final String name = seller?.name ?? 'Desconhecido';
    _log('sellerNameById', 'Return: $name');
    return name;
  }

  String? sellerContactById(int id) {
    _log('sellerContactById', 'Resolving seller contact for id=$id');
    if (_currentUser?.id == id) {
      final String? contact = _currentUser?.contact;
      _log('sellerContactById', 'Return: ${contact ?? '-'} (current user)');
      return contact;
    }

    final AppUser? seller = _sellers
        .where((AppUser u) => u.id == id)
        .firstOrNull;
    final String? contact = seller?.contact;
    _log('sellerContactById', 'Return: ${contact ?? '-'}');
    return contact;
  }

  Map<int, int> soldQuantityBySeller() {
    _log('soldQuantityBySeller', 'Calculating sold quantity grouped by seller');
    final Map<int, int> result = <int, int>{};
    for (final Ticket ticket in _tickets) {
      if (!ticket.isSold || ticket.sellerId == null) {
        continue;
      }
      result[ticket.sellerId!] = (result[ticket.sellerId!] ?? 0) + 1;
    }
    _log(
      'soldQuantityBySeller',
      'Return: ${result.length} seller group(s) data=$result',
    );
    return result;
  }

  Map<String, int> soldQuantityByBuyer() {
    _log('soldQuantityByBuyer', 'Calculating sold quantity grouped by buyer');
    final Map<String, int> result = <String, int>{};
    for (final Ticket ticket in _tickets) {
      if (!ticket.isSold) {
        continue;
      }

      final String buyer =
          (ticket.buyerName == null || ticket.buyerName!.trim().isEmpty)
          ? 'Sem nome'
          : ticket.buyerName!.trim();

      result[buyer] = (result[buyer] ?? 0) + 1;
    }

    _log(
      'soldQuantityByBuyer',
      'Return: ${result.length} buyer group(s) data=$result',
    );
    return result;
  }

  int soldTotalTickets() {
    final int total = soldQuantityBySeller().values.fold(
      0,
      (int sum, int quantity) => sum + quantity,
    );
    _log('soldTotalTickets', 'Return: total=$total | ${_stateSummary()}');
    return total;
  }

  double soldTotalValue() {
    final double value = soldTotalTickets() * 2.0;
    _log('soldTotalValue', 'Return: value=$value | ${_stateSummary()}');
    return value;
  }

  Future<void> logError({
    required String source,
    required String message,
    String? operation,
    String? stackTrace,
    Map<String, dynamic>? payload,
  }) async {
    try {
      await _client.rpc(
        'app_log_error',
        params: <String, dynamic>{
          'p_source': source,
          'p_error_message': message,
          'p_operation': operation,
          'p_stack_trace': stackTrace,
          'p_payload': payload,
          'p_token': _sessionToken,
        },
      );
    } catch (e) {
      _log('logError', 'Failed to persist error log: $e');
    }
  }

  String formatNumber(int number) {
    final String formatted = number.toString().padLeft(4, '0');
    _log('formatNumber', 'Return: $formatted from number=$number');
    return formatted;
  }

  Future<bool> _validateSessionAndBootstrap() async {
    _log(
      '_validateSessionAndBootstrap',
      'Validating session token in backend | ${_stateSummary()}',
    );
    final String token = _sessionToken!;

    try {
      final dynamic raw = await _client.rpc(
        'app_validate_session',
        params: <String, dynamic>{'p_token': token},
      );

      if (raw == null) {
        _log(
          '_validateSessionAndBootstrap',
          'Return: false (null response) | ${_stateSummary()}',
        );
        return false;
      }

      final Map<String, dynamic> payload = Map<String, dynamic>.from(
        raw as Map,
      );
      _applyAuthPayload(payload);
      await _bootstrap();
      _log('_validateSessionAndBootstrap', 'Return: true | ${_stateSummary()}');
      return true;
    } catch (e, s) {
      await logError(
        source: 'LotteryRepository',
        operation: '_validateSessionAndBootstrap',
        message: e.toString(),
        stackTrace: s.toString(),
        payload: <String, dynamic>{'phase': 'init_session_validation'},
      );

      if (_isSessionInvalidError(e)) {
        _log(
          '_validateSessionAndBootstrap',
          'Session invalid/expired, returning false to force login | error=$e',
        );
        return false;
      }

      rethrow;
    }
  }

  bool _isSessionInvalidError(Object error) {
    final String text = error.toString().toLowerCase();
    return text.contains('sessao invalida') ||
        text.contains('sessao expirada') ||
        text.contains('sessao inexistente');
  }

  void _applyAuthPayload(Map<String, dynamic> payload) {
    _log(
      '_applyAuthPayload',
      'Applying auth payload to local state | payloadKeys=${payload.keys.toList()}',
    );
    final Map<String, dynamic> user = Map<String, dynamic>.from(
      payload['user'] as Map? ?? <String, dynamic>{},
    );
    _currentUser = AppUser.fromJson(user);
    _currentCityId = payload['city_id'] as int? ?? _currentUser?.cityId;
    _log(
      '_applyAuthPayload',
      'Applied userId=${_currentUser?.id} cityId=$_currentCityId | ${_stateSummary()}',
    );
  }

  Future<void> _bootstrap() async {
    _log('_bootstrap', 'Loading bootstrap payload | ${_stateSummary()}');
    final String token = _requireToken();

    final dynamic raw = await _client.rpc(
      'app_bootstrap',
      params: <String, dynamic>{'p_token': token},
    );

    final Map<String, dynamic> data = Map<String, dynamic>.from(raw as Map);

    final Map<String, dynamic> user = Map<String, dynamic>.from(
      data['user'] as Map? ?? <String, dynamic>{},
    );
    _currentUser = AppUser.fromJson(user);

    _currentCityId = data['city_id'] as int? ?? _currentCityId;

    final List<dynamic> sellersRaw =
        (data['sellers'] as List<dynamic>? ?? <dynamic>[]);
    _sellers = sellersRaw
        .map(
          (dynamic item) =>
              AppUser.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .where((AppUser item) => !item.isAdmin)
        .toList();

    final List<dynamic> citiesRaw =
        (data['cities'] as List<dynamic>? ?? <dynamic>[]);
    _cities = citiesRaw
        .map(
          (dynamic item) =>
              AppCity.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();

    final List<dynamic> ticketsRaw =
        (data['tickets'] as List<dynamic>? ?? <dynamic>[]);
    _tickets = ticketsRaw
        .map(
          (dynamic item) =>
              Ticket.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();

    _sales = _tickets
        .where((Ticket ticket) => ticket.isSold && ticket.sellerId != null)
        .toList()
        .asMap()
        .entries
        .map(
          (MapEntry<int, Ticket> entry) => Sale(
            id: entry.key + 1,
            ticketId: entry.value.id,
            value: 2.0,
            sellerId: entry.value.sellerId!,
            createdAt: entry.value.soldAt ?? entry.value.createdAt,
          ),
        )
        .toList();

    _log(
      '_bootstrap',
      'Loaded user=${_currentUser?.id} city=$_currentCityId tickets=${_tickets.length} sellers=${_sellers.length} cities=${_cities.length} | ${_stateSummary()}',
    );
  }

  String _requireToken() {
    final String? token = _sessionToken;
    if (token == null) {
      _log('_requireToken', 'Throwing: session expired');
      throw Exception('Sessao expirada. Faça login novamente.');
    }
    _log(
      '_requireToken',
      'Return: token available | tokenPrefix=${token.substring(0, token.length > 8 ? 8 : token.length)}***',
    );
    return token;
  }

  Future<void> _clearSession() async {
    _log('_clearSession', 'Clearing persisted session | ${_stateSummary()}');
    _sessionToken = null;
    await _prefs?.remove(_sessionTokenKey);
    await _prefs?.remove(_sessionExpiresAtKey);
    _log('_clearSession', 'Session cleared | ${_stateSummary()}');
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
