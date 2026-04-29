// ignore_for_file: avoid_print

import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/app_user.dart';
import '../models/ticket.dart';
import '../services/ticket_image_service.dart';
import '../viewmodels/app_view_model.dart';

void _log(String method, String message) {
  print('In HomeView, Method: $method, $message');
}

class HomeView extends StatelessWidget {
  const HomeView({super.key, required this.viewModel});

  final AppViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    _log('build', 'Building HomeView with currentTab=${viewModel.currentTab}');
    final bool isAdmin = viewModel.isAdmin;
    final Widget ticketsTab = _TicketsTab(viewModel: viewModel);
    final Widget manageTab = _ManageTab(viewModel: viewModel);
    final Widget statsTab = _StatsTab(viewModel: viewModel);

    final int selectedNavIndex = isAdmin
        ? viewModel.currentTab
        : (viewModel.currentTab == 2 ? 1 : 0);
    final Widget currentBody = isAdmin
        ? <Widget>[ticketsTab, manageTab, statsTab][viewModel.currentTab]
        : (viewModel.currentTab == 2 ? statsTab : ticketsTab);

    return Scaffold(
      appBar: AppBar(
        title: Text(viewModel.currentUser?.name ?? ''),
        actions: <Widget>[
          if (viewModel.cities.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: viewModel.currentCityId,
                  hint: const Text('Cidade'),
                  items: viewModel.cities.map((city) {
                    return DropdownMenuItem<int>(
                      value: city.id,
                      child: Text(city.name),
                    );
                  }).toList(),
                  onChanged: viewModel.isBusy
                      ? null
                      : (int? value) {
                          if (value != null) {
                            _log(
                              'build.onChangedCity',
                              'User selected cityId=$value currentCityId=${viewModel.currentCityId}',
                            );
                            viewModel.switchCity(value);
                          }
                        },
                ),
              ),
            ),
          IconButton(
            onPressed: viewModel.isBusy ? null : viewModel.logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: currentBody,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedNavIndex,
        onDestinationSelected: (int index) {
          if (isAdmin) {
            viewModel.setTab(index);
            return;
          }
          viewModel.setTab(index == 0 ? 0 : 2);
        },
        destinations: isAdmin
            ? const <NavigationDestination>[
                NavigationDestination(
                  icon: Icon(Icons.search),
                  label: 'Bilhetes',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings),
                  label: 'Gerenciar',
                ),
                NavigationDestination(
                  icon: Icon(Icons.bar_chart),
                  label: 'Estatisticas',
                ),
              ]
            : const <NavigationDestination>[
                NavigationDestination(
                  icon: Icon(Icons.search),
                  label: 'Bilhetes',
                ),
                NavigationDestination(
                  icon: Icon(Icons.bar_chart),
                  label: 'Estatisticas',
                ),
              ],
      ),
    );
  }
}

class _TicketsTab extends StatefulWidget {
  const _TicketsTab({required this.viewModel});

  final AppViewModel viewModel;

  @override
  State<_TicketsTab> createState() => _TicketsTabState();
}

class _TicketsTabState extends State<_TicketsTab> {
  final TextEditingController _searchController = TextEditingController();
  final TicketImageService _ticketImageService = TicketImageService();
  final Set<int> _selectedTicketIds = <int>{};

  String _digitsOnly(String input) {
    return input.replaceAll(RegExp(r'[^0-9]'), '');
  }

  String _friendlyMissingBuyerMessage({
    required bool missingName,
    required bool missingPhone,
  }) {
    if (missingName && missingPhone) {
      return 'Informe nome e telefone do comprador para concluir a venda.';
    }
    if (missingName) {
      return 'Informe o nome do comprador para concluir a venda.';
    }
    return 'Informe o telefone completo do comprador para concluir a venda.';
  }

  Future<File> _createTicketImageFromData({
    required Ticket ticket,
    required String buyerName,
    required String buyerPhoneDigits,
  }) async {
    final List<int> nums = ticket.numbers.toList()..sort();
    while (nums.length < 4) {
      nums.add(0);
    }

    final int? sellerId = ticket.sellerId ?? widget.viewModel.currentUser?.id;
    final String sellerName = sellerId == null
        ? (widget.viewModel.currentUser?.name ?? 'Sem vendedor')
        : widget.viewModel.sellerNameById(sellerId);
    final String sellerPhoneDigits = sellerId == null
        ? _digitsOnly(widget.viewModel.currentUser?.contact ?? '')
        : _digitsOnly(widget.viewModel.sellerContactById(sellerId) ?? '');
    final String saleDate = DateFormat(
      'dd/MM/yyyy HH:mm',
    ).format(ticket.soldAt ?? DateTime.now());

    return _ticketImageService.createTicketImageFile(
      numero1: nums[0],
      numero2: nums[1],
      numero3: nums[2],
      numero4: nums[3],
      nome_comprador: buyerName,
      numero_comprador: buyerPhoneDigits,
      nome_vendedor: sellerName,
      numero_vendedor: sellerPhoneDigits,
      data_venda: saleDate,
      fileName:
          'ticket_${ticket.id}_${DateTime.now().millisecondsSinceEpoch}.png',
    );
  }

  Future<void> _shareFilesDirectly(List<File> files) async {
    if (files.isEmpty) {
      return;
    }
    if (files.length == 1) {
      await _ticketImageService.shareTicketGeneric(files.first);
      return;
    }
    await _ticketImageService.shareManyGeneric(files);
  }

  Future<void> _shareSelectedTickets() async {
    final List<Ticket> selected = widget.viewModel.searchedTickets
        .where((Ticket t) => _selectedTicketIds.contains(t.id))
        .toList();
    if (selected.isEmpty) {
      return;
    }

    final List<Ticket> invalid = selected.where((Ticket t) {
      final String buyerName = (t.buyerName ?? '').trim();
      final String buyerPhone = _digitsOnly(t.buyerContact ?? '');
      return !t.isSold || buyerName.isEmpty || buyerPhone.length != 11;
    }).toList();

    if (invalid.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Selecione apenas bilhetes vendidos com nome e telefone do comprador.',
          ),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Criando imagem do bilhete...')),
    );

    final List<File> files = await Future.wait(
      selected.map((Ticket t) {
        return _createTicketImageFromData(
          ticket: t,
          buyerName: (t.buyerName ?? '').trim(),
          buyerPhoneDigits: _digitsOnly(t.buyerContact ?? ''),
        );
      }),
    );

    if (!mounted) {
      return;
    }

    await _shareFilesDirectly(files);
    if (!mounted) {
      return;
    }
    setState(() => _selectedTicketIds.clear());
  }

  @override
  void initState() {
    super.initState();
    _log(
      '_TicketsTabState.initState',
      'Initializing tickets tab and loading default search',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _log(
          '_TicketsTabState.initState',
          'Widget unmounted before initial search',
        );
        return;
      }
      widget.viewModel.searchTickets('');
    });
  }

  @override
  void dispose() {
    _log('_TicketsTabState.dispose', 'Disposing search controller');
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _toggleSold(Ticket ticket, bool newValue) async {
    _log(
      '_TicketsTabState._toggleSold',
      'Updating ticketId=${ticket.id} sold=$newValue',
    );
    _BuyerDialogResult? buyer;
    if (newValue) {
      buyer = await _askBuyerData();
      if (!mounted) {
        return;
      }
      if (buyer == null) {
        _log(
          '_TicketsTabState._toggleSold',
          'User canceled buyer dialog, returning',
        );
        return;
      }

      final bool missingName = buyer.name.trim().isEmpty;
      final bool missingPhone = _digitsOnly(buyer.phone).length != 11;
      if (missingName || missingPhone) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _friendlyMissingBuyerMessage(
                missingName: missingName,
                missingPhone: missingPhone,
              ),
            ),
          ),
        );
        return;
      }
    } else if (ticket.isSold) {
      final bool confirmed = await _confirmUndoSale();
      if (!mounted) {
        return;
      }
      if (!confirmed) {
        _log(
          '_TicketsTabState._toggleSold',
          'Undo sale canceled by user for ticketId=${ticket.id}',
        );
        return;
      }
    }

    final bool success = await widget.viewModel.toggleTicketSold(
      ticketId: ticket.id,
      sold: newValue,
      buyerName: buyer?.name,
      buyerContact: buyer?.phone,
    );

    if (!mounted) {
      return;
    }

    if (success) {
      _log(
        '_TicketsTabState._toggleSold',
        'Update finished mounted=$mounted success=$success',
      );

      if (newValue && buyer != null) {
        final List<Ticket> matched = widget.viewModel.searchedTickets
            .where((Ticket t) => t.id == ticket.id)
            .toList();
        final Ticket soldTicket = matched.isNotEmpty ? matched.first : ticket;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Criando imagem do bilhete...')),
        );

        final File file = await _createTicketImageFromData(
          ticket: soldTicket,
          buyerName: buyer.name.trim(),
          buyerPhoneDigits: _digitsOnly(buyer.phone),
        );
        if (!mounted) {
          return;
        }
        await _shareFilesDirectly(<File>[file]);
      }
      return;
    }

    const String message =
        'Nao foi possivel atualizar o bilhete. Tente novamente.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _confirmUndoSale() async {
    _log('_TicketsTabState._confirmUndoSale', 'Opening undo-sale confirmation');
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirmar desfazer venda'),
          content: const Text(
            'Deseja realmente desfazer esta venda? O comprador sera removido e o bilhete ficara sem vendedor.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Desfazer venda'),
            ),
          ],
        );
      },
    );
    final bool confirmed = result ?? false;
    _log('_TicketsTabState._confirmUndoSale', 'Return: $confirmed');
    return confirmed;
  }

  Future<_BuyerDialogResult?> _askBuyerData() async {
    _log('_TicketsTabState._askBuyerData', 'Opening buyer name/phone dialog');
    String buyerName = '';
    String buyerPhone = '';
    final _BuyerDialogResult? result = await showDialog<_BuyerDialogResult>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Dados do comprador'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                inputFormatters: <TextInputFormatter>[
                  LengthLimitingTextInputFormatter(20),
                ],
                decoration: const InputDecoration(hintText: 'Nome (opcional)'),
                onChanged: (String value) {
                  buyerName = value;
                },
              ),
              const SizedBox(height: 8),
              TextField(
                keyboardType: TextInputType.phone,
                inputFormatters: <TextInputFormatter>[
                  _BrazilPhoneTextInputFormatter(),
                ],
                decoration: const InputDecoration(hintText: '(99) 99999-9999'),
                onChanged: (String value) {
                  buyerPhone = value;
                },
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(
                context,
              ).pop(const _BuyerDialogResult(name: '', phone: '')),
              child: const Text('Sem dados'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(
                _BuyerDialogResult(
                  name: buyerName.trim(),
                  phone: _digitsOnly(buyerPhone),
                ),
              ),
              child: const Text('Confirmar'),
            ),
          ],
        );
      },
    );
    _log(
      '_TicketsTabState._askBuyerData',
      'Dialog return: name=${result?.name ?? 'null'} phone=${result?.phone ?? 'null'}',
    );
    return result;
  }

  @override
  Widget build(BuildContext context) {
    _log('_TicketsTabState.build', 'Building tickets tab');
    final List<Ticket> tickets = widget.viewModel.searchedTickets;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: <Widget>[
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              labelText: 'Buscar por nome, numero (0001) ou data (dd/MM/yyyy)',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                onPressed: () {
                  _searchController.clear();
                  widget.viewModel.searchTickets('');
                },
                icon: const Icon(Icons.clear),
              ),
            ),
            onSubmitted: widget.viewModel.searchTickets,
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              FilledButton.icon(
                onPressed: () {
                  _log(
                    '_TicketsTabState.build.onSearchPressed',
                    'Pressed search with query="${_searchController.text}"',
                  );
                  widget.viewModel.searchTickets(_searchController.text);
                },
                icon: const Icon(Icons.search),
                label: const Text('Procurar'),
              ),
              const SizedBox(width: 12),
              Text('Encontrados: ${tickets.length}'),
              const SizedBox(width: 12),
              if (_selectedTicketIds.isNotEmpty)
                FilledButton.icon(
                  onPressed: _shareSelectedTickets,
                  icon: const Icon(Icons.share_outlined),
                  label: Text('Enviar (${_selectedTicketIds.length})'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (tickets.isEmpty)
            const Expanded(
              child: Center(child: Text('Nenhum bilhete encontrado.')),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: tickets.length,
                itemBuilder: (BuildContext context, int index) {
                  final Ticket ticket = tickets[index];
                  final Color bg = ticket.isSold
                      ? const Color(0xFFFFF3C4)
                      : const Color(0xFFFFFFFF);
                  return Card(
                    color: bg,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Checkbox(
                            value: _selectedTicketIds.contains(ticket.id),
                            onChanged: (bool? value) {
                              setState(() {
                                if (value == true) {
                                  _selectedTicketIds.add(ticket.id);
                                } else {
                                  _selectedTicketIds.remove(ticket.id);
                                }
                              });
                            },
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  ticket.numbers
                                      .map(widget.viewModel.formatNumber)
                                      .join(' - '),
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 8),
                                Text('Comprador: ${ticket.buyerName ?? '-'}'),
                                Text('Telefone: ${ticket.buyerContact ?? '-'}'),
                                Text(
                                  'Vendedor: ${ticket.sellerId == null ? '-' : widget.viewModel.sellerNameById(ticket.sellerId!)}',
                                ),
                                Text(
                                  'Criado: ${DateFormat('dd/MM/yyyy').format(ticket.createdAt)}',
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              const Text('Vendido'),
                              Switch(
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                value: ticket.isSold,
                                onChanged:
                                    (!widget.viewModel.isAdmin && ticket.isSold)
                                    ? null
                                    : (bool value) =>
                                          _toggleSold(ticket, value),
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
    );
  }
}

class _BuyerDialogResult {
  const _BuyerDialogResult({required this.name, required this.phone});

  final String name;
  final String phone;
}

class _ManageTab extends StatefulWidget {
  const _ManageTab({required this.viewModel});

  final AppViewModel viewModel;

  @override
  State<_ManageTab> createState() => _ManageTabState();
}

class _ManageTabState extends State<_ManageTab> {
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _cityNameController = TextEditingController();
  final TextEditingController _sellerNameController = TextEditingController();
  final TextEditingController _sellerContactController =
      TextEditingController();
  final TextEditingController _sellerLoginController = TextEditingController();
  final TextEditingController _sellerPasswordController =
      TextEditingController();
  final TextEditingController _editSellerNameController =
      TextEditingController();
  final TextEditingController _editSellerContactController =
      TextEditingController();
  final TextEditingController _editSellerLoginController =
      TextEditingController();
  final TextEditingController _editSellerPasswordController =
      TextEditingController();
  final TextEditingController _deleteTicketNumberController =
      TextEditingController();
  final TextEditingController _deleteRangeStartController =
      TextEditingController();
  final TextEditingController _deleteRangeEndController =
      TextEditingController();
  final TextEditingController _rangeStartController = TextEditingController();
  final TextEditingController _rangeEndController = TextEditingController();
  final TextEditingController _numbersController = TextEditingController();
  final TextEditingController _quantityAssignController =
      TextEditingController();
  final PageController _ticketCrudController = PageController(
    viewportFraction: 0.94,
  );
  final PageController _sellerCrudController = PageController(
    viewportFraction: 0.94,
  );

  int? _selectedSellerId;
  int? _selectedSellerCrudId;
  int _currentCrudPage = 0;
  int _currentSellerCrudPage = 0;

  String _digitsOnly(String input) {
    return input.replaceAll(RegExp(r'[^0-9]'), '');
  }

  @override
  void initState() {
    super.initState();
    _log('_ManageTabState.initState', 'Initializing manage tab');
    final List<AppUser> sellers = widget.viewModel.sellers;
    _selectedSellerId = sellers.isEmpty ? null : sellers.first.id;
    _selectedSellerCrudId = sellers.isEmpty ? null : sellers.first.id;
    _fillEditSellerFields(_selectedSellerCrudId);
  }

  @override
  void dispose() {
    _log('_ManageTabState.dispose', 'Disposing manage tab controllers');
    _quantityController.dispose();
    _cityNameController.dispose();
    _sellerNameController.dispose();
    _sellerContactController.dispose();
    _sellerLoginController.dispose();
    _sellerPasswordController.dispose();
    _editSellerNameController.dispose();
    _editSellerContactController.dispose();
    _editSellerLoginController.dispose();
    _editSellerPasswordController.dispose();
    _deleteTicketNumberController.dispose();
    _deleteRangeStartController.dispose();
    _deleteRangeEndController.dispose();
    _rangeStartController.dispose();
    _rangeEndController.dispose();
    _numbersController.dispose();
    _ticketCrudController.dispose();
    _sellerCrudController.dispose();
    super.dispose();
  }

  AppUser? _findSellerById(int? sellerId) {
    if (sellerId == null) {
      return null;
    }
    for (final AppUser seller in widget.viewModel.sellers) {
      if (seller.id == sellerId) {
        return seller;
      }
    }
    return null;
  }

  int? _safeSellerId(int? sellerId) {
    return _findSellerById(sellerId)?.id;
  }

  void _fillEditSellerFields(int? sellerId) {
    final AppUser? seller = _findSellerById(sellerId);
    if (seller == null) {
      _editSellerNameController.clear();
      _editSellerContactController.clear();
      _editSellerLoginController.clear();
      _editSellerPasswordController.clear();
      return;
    }
    _editSellerNameController.text = seller.name;
    _editSellerContactController.text = seller.contact ?? '';
    _editSellerLoginController.text = seller.login;
    _editSellerPasswordController.clear();
  }

  Future<void> _generate() async {
    _log('_ManageTabState._generate', 'Generating tickets requested by UI');
    final int quantity = int.tryParse(_quantityController.text.trim()) ?? 0;
    final bool success = await widget.viewModel.generateTickets(quantity);
    if (!mounted) {
      return;
    }

    final String message = success
        ? 'Bilhetes criados com sucesso.'
        : 'Nao foi possivel criar os bilhetes. Tente novamente.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _assignByRange() async {
    _log('_ManageTabState._assignByRange', 'Assigning tickets by range via UI');
    final int? sellerId = _safeSellerId(_selectedSellerId);
    if (sellerId == null) {
      _log('_ManageTabState._assignByRange', 'No seller selected, returning');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione um vendedor valido.')),
      );
      return;
    }

    final int start = int.tryParse(_rangeStartController.text.trim()) ?? -1;
    final int end = int.tryParse(_rangeEndController.text.trim()) ?? -1;

    final int? updated = await widget.viewModel.assignByRange(
      start: start,
      end: end,
      sellerId: sellerId,
    );

    if (!mounted) {
      return;
    }

    final String message = updated == null
        ? 'Nao foi possivel atribuir bilhetes agora. Tente novamente.'
        : '$updated bilhete(s) atribuido(s) por intervalo.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _assignByNumbers() async {
    _log(
      '_ManageTabState._assignByNumbers',
      'Assigning tickets by explicit numbers via UI',
    );
    final int? sellerId = _safeSellerId(_selectedSellerId);
    if (sellerId == null) {
      _log('_ManageTabState._assignByNumbers', 'No seller selected, returning');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione um vendedor valido.')),
      );
      return;
    }

    final List<int> numbers = _numbersController.text
        .split(',')
        .map((String value) => int.tryParse(value.trim()))
        .whereType<int>()
        .toList();

    final int? updated = await widget.viewModel.assignByNumbers(
      numbers: numbers,
      sellerId: sellerId,
    );

    if (!mounted) {
      return;
    }

    final String message = updated == null
        ? 'Nao foi possivel atribuir bilhetes agora. Tente novamente.'
        : '$updated bilhete(s) atribuido(s) por numeros.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _assignByQuantity() async {
    _log(
      '_ManageTabState._assignByQuantity',
      'Assigning tickets by quantity via UI',
    );
    final int? sellerId = _safeSellerId(_selectedSellerId);
    if (sellerId == null) {
      _log(
        '_ManageTabState._assignByQuantity',
        'No seller selected, returning',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione um vendedor valido.')),
      );
      return;
    }

    final int quantity =
        int.tryParse(_quantityAssignController.text.trim()) ?? -1;

    final int? updated = await widget.viewModel.assignByQuantity(
      quantity: quantity,
      sellerId: sellerId,
    );

    if (!mounted) {
      return;
    }

    final String message = updated == null
        ? 'Nao foi possivel atribuir bilhetes agora. Tente novamente.'
        : '$updated bilhete(s) atribuido(s) por quantidade.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _createCity() async {
    final String cityName = _cityNameController.text.trim();
    final bool success = await widget.viewModel.createCity(cityName);
    if (!mounted) {
      return;
    }

    final String message = success
        ? 'Cidade criada com sucesso.'
        : 'Nao foi possivel criar a cidade. Tente novamente.';

    if (success) {
      _cityNameController.clear();
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _createSeller() async {
    final String userName = _sellerNameController.text.trim();
    final String userContact = _digitsOnly(_sellerContactController.text);
    final String login = _sellerLoginController.text.trim();
    final String password = _sellerPasswordController.text;

    final bool success = await widget.viewModel.createSeller(
      userName: userName,
      userContact: userContact,
      login: login,
      password: password,
    );

    if (!mounted) {
      return;
    }

    final String message = success
        ? 'Conta de vendedor criada com sucesso.'
        : _createSellerErrorMessage(widget.viewModel.errorMessage);

    if (success) {
      _sellerNameController.clear();
      _sellerContactController.clear();
      _sellerLoginController.clear();
      _sellerPasswordController.clear();
      final List<AppUser> sellers = widget.viewModel.sellers;
      if (sellers.isNotEmpty) {
        setState(() {
          _selectedSellerId = sellers.first.id;
          _selectedSellerCrudId = sellers.first.id;
          _fillEditSellerFields(_selectedSellerCrudId);
        });
      }
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _createSellerErrorMessage(String? rawError) {
    final String raw = (rawError ?? '').trim();
    final String normalized = raw.toLowerCase();

    if (normalized.contains('login ja existe')) {
      return 'Login ja existe.';
    }
    if (normalized.contains('nome do vendedor e obrigatorio')) {
      return 'Nome do vendedor e obrigatorio.';
    }
    if (normalized.contains(
      'nome do vendedor deve ter no maximo 20 caracteres',
    )) {
      return 'Nome do vendedor deve ter no maximo 20 caracteres.';
    }
    if (normalized.contains('contato do vendedor deve conter 11 digitos')) {
      return 'Contato do vendedor deve conter 11 digitos.';
    }
    if (normalized.contains('login do vendedor e obrigatorio')) {
      return 'Login do vendedor e obrigatorio.';
    }

    return 'Ocorreu um erro ao criar conta de vendedor.';
  }

  Future<void> _updateSeller() async {
    final int? sellerId = _safeSellerId(_selectedSellerCrudId);
    if (sellerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione um vendedor para editar.')),
      );
      return;
    }

    final bool success = await widget.viewModel.updateSeller(
      sellerId: sellerId,
      userName: _editSellerNameController.text.trim(),
      userContact: _digitsOnly(_editSellerContactController.text),
      login: _editSellerLoginController.text.trim(),
      password: _editSellerPasswordController.text,
    );

    if (!mounted) {
      return;
    }

    final String message = success
        ? 'Conta de vendedor atualizada com sucesso.'
        : 'Nao foi possivel atualizar a conta do vendedor. Tente novamente.';

    if (success) {
      _editSellerPasswordController.clear();
      _fillEditSellerFields(sellerId);
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _deleteSeller() async {
    final int? sellerId = _safeSellerId(_selectedSellerCrudId);
    if (sellerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione um vendedor para excluir.')),
      );
      return;
    }

    final bool success = await widget.viewModel.deleteSeller(sellerId);

    if (!mounted) {
      return;
    }

    final String message = success
        ? 'Conta de vendedor excluida com sucesso.'
        : 'Nao foi possivel excluir a conta do vendedor. Tente novamente.';

    if (success) {
      final List<AppUser> sellers = widget.viewModel.sellers;
      setState(() {
        _selectedSellerId = sellers.isEmpty ? null : sellers.first.id;
        _selectedSellerCrudId = sellers.isEmpty ? null : sellers.first.id;
        _fillEditSellerFields(_selectedSellerCrudId);
      });
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _deleteTicketByNumber() async {
    final int number =
        int.tryParse(_deleteTicketNumberController.text.trim()) ?? -1;
    final bool success = await widget.viewModel.deleteTicketByNumber(number);

    if (!mounted) {
      return;
    }

    final String message = success
        ? 'Bilhete excluido com sucesso.'
        : 'Nao foi possivel excluir o bilhete. Tente novamente.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _deleteTicketByRange() async {
    final int start =
        int.tryParse(_deleteRangeStartController.text.trim()) ?? -1;
    final int end = int.tryParse(_deleteRangeEndController.text.trim()) ?? -1;
    final int? deleted = await widget.viewModel.deleteTicketsByRange(
      start: start,
      end: end,
    );

    if (!mounted) {
      return;
    }

    final String message = deleted == null
        ? 'Nao foi possivel excluir bilhetes por intervalo. Tente novamente.'
        : '$deleted bilhete(s) excluido(s) por intervalo.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildSectionContainer({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF9BD4B5)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x1A2F6F4E),
            blurRadius: 14,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F7EE),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: const Color(0xFF1F6B46)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildCrudCard({
    required BuildContext context,
    required String title,
    required String description,
    required IconData icon,
    required List<Widget> content,
    required Widget actionButton,
  }) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF9BD4B5)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x1A2F6F4E),
            blurRadius: 14,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F7EE),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: const Color(0xFF1F6B46)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(description),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: content,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: actionButton),
        ],
      ),
    );
  }

  Widget _buildTicketCrudCarousel(BuildContext context) {
    final List<({String title, Widget card})>
    cards = <({String title, Widget card})>[
      (
        title: 'Gerar Bilhetes',
        card: _buildCrudCard(
          context: context,
          title: 'Gerar Bilhetes',
          description:
              'Gera lotes aleatórios com capacidade máxima simultânea de 2500.',
          icon: Icons.auto_awesome,
          content: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF1FBF5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFCDEBD9)),
              ),
              child: Text(
                'Total atual: ${widget.viewModel.totalTickets} bilhete(s)',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _quantityController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Quantidade',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.confirmation_num_outlined),
              ),
            ),
          ],
          actionButton: FilledButton.icon(
            onPressed: _generate,
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('Gerar bilhetes'),
          ),
        ),
      ),
      (
        title: 'Excluir Bilhete Individual',
        card: _buildCrudCard(
          context: context,
          title: 'Excluir Bilhete Individual',
          description: 'Exclui um bilhete por numero (0000 a 9999).',
          icon: Icons.delete_outline,
          content: <Widget>[
            TextField(
              controller: _deleteTicketNumberController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Numero do bilhete (ex: 42)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.tag_outlined),
              ),
            ),
          ],
          actionButton: FilledButton.icon(
            onPressed: _deleteTicketByNumber,
            icon: const Icon(Icons.delete_forever_outlined),
            label: const Text('Excluir bilhete'),
          ),
        ),
      ),
      (
        title: 'Excluir por Intervalo',
        card: _buildCrudCard(
          context: context,
          title: 'Excluir por Intervalo',
          description:
              'Exclui bilhetes que possuam numeros dentro do intervalo.',
          icon: Icons.delete_sweep_outlined,
          content: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _deleteRangeStartController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'De (ex: 0)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _deleteRangeEndController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Ate (ex: 500)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Minimo: 1, Maximo 9999',
              style: TextStyle(color: Colors.grey),
            ),
          ],
          actionButton: FilledButton.icon(
            onPressed: _deleteTicketByRange,
            icon: const Icon(Icons.delete_sweep),
            label: const Text('Excluir por intervalo'),
          ),
        ),
      ),
    ];

    final bool hasLeft = _currentCrudPage > 0;
    final bool hasRight = _currentCrudPage < cards.length - 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          height: 330,
          child: Stack(
            children: <Widget>[
              PageView.builder(
                controller: _ticketCrudController,
                itemCount: cards.length,
                onPageChanged: (int index) {
                  setState(() {
                    _currentCrudPage = index;
                  });
                },
                itemBuilder: (BuildContext context, int index) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: SizedBox.expand(child: cards[index].card),
                  );
                },
              ),
              if (hasLeft)
                Positioned(
                  left: 2,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Material(
                      color: Colors.white.withValues(alpha: 0.9),
                      shape: const CircleBorder(),
                      child: IconButton(
                        onPressed: () {
                          _ticketCrudController.previousPage(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOut,
                          );
                        },
                        icon: const Icon(Icons.arrow_back_ios_new_rounded),
                      ),
                    ),
                  ),
                ),
              if (hasRight)
                Positioned(
                  right: 2,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Material(
                      color: Colors.white.withValues(alpha: 0.9),
                      shape: const CircleBorder(),
                      child: IconButton(
                        onPressed: () {
                          _ticketCrudController.nextPage(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOut,
                          );
                        },
                        icon: const Icon(Icons.arrow_forward_ios_rounded),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List<Widget>.generate(cards.length, (int index) {
            final bool selected = index == _currentCrudPage;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              height: 7,
              width: selected ? 18 : 7,
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFF1F6B46)
                    : const Color(0xFFD2E9DB),
                borderRadius: BorderRadius.circular(99),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildSellerCrudCarousel(BuildContext context) {
    final List<({String title, Widget card})>
    cards = <({String title, Widget card})>[
      (
        title: 'Criar Conta de Vendedor',
        card: _buildCrudCard(
          context: context,
          title: 'Criar Conta de Vendedor',
          description: 'Cria uma conta de vendedor com perfil nao-admin.',
          icon: Icons.person_add_alt_1,
          content: <Widget>[
            TextField(
              controller: _sellerNameController,
              inputFormatters: <TextInputFormatter>[
                LengthLimitingTextInputFormatter(20),
              ],
              decoration: const InputDecoration(
                labelText: 'Nome',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.badge_outlined),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _sellerContactController,
              keyboardType: TextInputType.phone,
              inputFormatters: <TextInputFormatter>[
                _BrazilPhoneTextInputFormatter(),
              ],
              decoration: const InputDecoration(
                labelText: 'Contato',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _sellerLoginController,
              decoration: const InputDecoration(
                labelText: 'Login',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.alternate_email_outlined),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _sellerPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Senha',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.password_outlined),
              ),
            ),
          ],
          actionButton: FilledButton.icon(
            onPressed: _createSeller,
            icon: const Icon(Icons.person_add),
            label: const Text('Criar conta de vendedor'),
          ),
        ),
      ),
      (
        title: 'Editar Conta de Vendedor',
        card: _buildCrudCard(
          context: context,
          title: 'Editar Conta de Vendedor',
          description:
              'Atualiza nome, contato, login e opcionalmente senha do vendedor.',
          icon: Icons.edit_note_outlined,
          content: <Widget>[
            DropdownButtonFormField<int>(
              initialValue: _safeSellerId(_selectedSellerCrudId),
              decoration: const InputDecoration(
                labelText: 'Vendedor',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person_outline),
              ),
              items: widget.viewModel.sellers.map((AppUser seller) {
                return DropdownMenuItem<int>(
                  value: seller.id,
                  child: Text(seller.name),
                );
              }).toList(),
              onChanged: (int? value) {
                setState(() {
                  _selectedSellerCrudId = value;
                  _fillEditSellerFields(value);
                });
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _editSellerNameController,
              inputFormatters: <TextInputFormatter>[
                LengthLimitingTextInputFormatter(20),
              ],
              decoration: const InputDecoration(
                labelText: 'Nome',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.badge_outlined),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _editSellerContactController,
              keyboardType: TextInputType.phone,
              inputFormatters: <TextInputFormatter>[
                _BrazilPhoneTextInputFormatter(),
              ],
              decoration: const InputDecoration(
                labelText: 'Contato',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _editSellerLoginController,
              decoration: const InputDecoration(
                labelText: 'Login',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.alternate_email_outlined),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _editSellerPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Nova senha (opcional)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.password_outlined),
              ),
            ),
          ],
          actionButton: FilledButton.icon(
            onPressed: _updateSeller,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Salvar alteracoes'),
          ),
        ),
      ),
      (
        title: 'Excluir Conta de Vendedor',
        card: _buildCrudCard(
          context: context,
          title: 'Excluir Conta de Vendedor',
          description: 'Remove a conta do vendedor selecionado.',
          icon: Icons.person_remove_outlined,
          content: <Widget>[
            DropdownButtonFormField<int>(
              initialValue: _safeSellerId(_selectedSellerCrudId),
              decoration: const InputDecoration(
                labelText: 'Vendedor',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person_outline),
              ),
              items: widget.viewModel.sellers.map((AppUser seller) {
                return DropdownMenuItem<int>(
                  value: seller.id,
                  child: Text(seller.name),
                );
              }).toList(),
              onChanged: (int? value) {
                setState(() {
                  _selectedSellerCrudId = value;
                  _fillEditSellerFields(value);
                });
              },
            ),
          ],
          actionButton: FilledButton.icon(
            onPressed: _deleteSeller,
            icon: const Icon(Icons.delete_forever_outlined),
            label: const Text('Excluir conta de vendedor'),
          ),
        ),
      ),
    ];

    final bool hasLeft = _currentSellerCrudPage > 0;
    final bool hasRight = _currentSellerCrudPage < cards.length - 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          height: 360,
          child: Stack(
            children: <Widget>[
              PageView.builder(
                controller: _sellerCrudController,
                itemCount: cards.length,
                onPageChanged: (int index) {
                  setState(() {
                    _currentSellerCrudPage = index;
                  });
                },
                itemBuilder: (BuildContext context, int index) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: SizedBox.expand(child: cards[index].card),
                  );
                },
              ),
              if (hasLeft)
                Positioned(
                  left: 2,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Material(
                      color: Colors.white.withValues(alpha: 0.9),
                      shape: const CircleBorder(),
                      child: IconButton(
                        onPressed: () {
                          _sellerCrudController.previousPage(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOut,
                          );
                        },
                        icon: const Icon(Icons.arrow_back_ios_new_rounded),
                      ),
                    ),
                  ),
                ),
              if (hasRight)
                Positioned(
                  right: 2,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Material(
                      color: Colors.white.withValues(alpha: 0.9),
                      shape: const CircleBorder(),
                      child: IconButton(
                        onPressed: () {
                          _sellerCrudController.nextPage(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOut,
                          );
                        },
                        icon: const Icon(Icons.arrow_forward_ios_rounded),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List<Widget>.generate(cards.length, (int index) {
            final bool selected = index == _currentSellerCrudPage;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              height: 7,
              width: selected ? 18 : 7,
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFF1F6B46)
                    : const Color(0xFFD2E9DB),
                borderRadius: BorderRadius.circular(99),
              ),
            );
          }),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    _log('_ManageTabState.build', 'Building manage tab');
    final bool admin = widget.viewModel.isAdmin;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: <Color>[Color(0xFF0F5132), Color(0xFF2D8A5F)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x333B7D5D),
                  blurRadius: 16,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0x33FFFFFF),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    admin ? Icons.admin_panel_settings : Icons.person,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        admin ? 'Painel Administrativo' : 'Painel do Vendedor',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        admin
                            ? 'Crie e distribua bilhetes com controle por cidade.'
                            : 'Busque bilhetes e gerencie apenas as vendas permitidas para voce.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFFE7F8EF),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (!admin)
            _buildSectionContainer(
              context: context,
              title: 'Acesso Restrito',
              subtitle: 'Visualizacao informativa para vendedor',
              icon: Icons.lock_outline,
              children: const <Widget>[
                Text(
                  'As funcoes de criação e atribuição de bilhetes sao exclusivas do administrador.',
                ),
              ],
            ),
          if (admin) ...<Widget>[
            _buildSectionContainer(
              context: context,
              title: 'Criação de Cidade',
              subtitle: 'Adiciona uma nova cidade no sistema',
              icon: Icons.location_city,
              children: <Widget>[
                TextField(
                  controller: _cityNameController,
                  decoration: const InputDecoration(
                    labelText: 'Nome da cidade',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.map_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _createCity,
                  icon: const Icon(Icons.add_location_alt_outlined),
                  label: const Text('Criar cidade'),
                ),
              ],
            ),
            _buildSellerCrudCarousel(context),
            const SizedBox(height: 16),
            _buildTicketCrudCarousel(context),
            const SizedBox(height: 16),
            _buildSectionContainer(
              context: context,
              title: 'Atribuição de Bilhetes',
              subtitle: 'Vincule por intervalo ou por números específicos',
              icon: Icons.hub_outlined,
              children: <Widget>[
                DropdownButtonFormField<int>(
                  initialValue: _safeSellerId(_selectedSellerId),
                  decoration: const InputDecoration(
                    labelText: 'Vendedor',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  items: widget.viewModel.sellers.map((AppUser seller) {
                    return DropdownMenuItem<int>(
                      value: seller.id,
                      child: Text(seller.name),
                    );
                  }).toList(),
                  onChanged: (int? value) {
                    setState(() {
                      _selectedSellerId = value;
                    });
                  },
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _rangeStartController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'De (ex: 1)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.filter_1),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _rangeEndController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Ate (ex: 30)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.filter_9_plus),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _assignByRange,
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('Atribuir por intervalo'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _numbersController,
                  decoration: const InputDecoration(
                    labelText: 'Números individuais (ex: 1,2,3,4)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.pin_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _assignByNumbers,
                  icon: const Icon(Icons.format_list_numbered),
                  label: const Text('Atribuir por números'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _quantityAssignController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Quantidade de bilhetes',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.shopping_cart_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _assignByQuantity,
                  icon: const Icon(Icons.assignment_outlined),
                  label: const Text('Atribuir por quantidade'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StatsTab extends StatelessWidget {
  const _StatsTab({required this.viewModel});

  final AppViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    _log('_StatsTab.build', 'Building stats tab');
    final bool isAdmin = viewModel.isAdmin;
    final Map<int, int> soldBySeller = viewModel.soldBySeller;
    final List<MapEntry<int, int>> entries = soldBySeller.entries.toList()
      ..sort(
        (MapEntry<int, int> a, MapEntry<int, int> b) =>
            b.value.compareTo(a.value),
      );
    final Map<String, int> soldByClient = viewModel.soldByClient;
    final List<MapEntry<String, int>> clientEntries =
        soldByClient.entries.toList()..sort(
          (MapEntry<String, int> a, MapEntry<String, int> b) =>
              b.value.compareTo(a.value),
        );

    final int maxY = entries.isEmpty
        ? 1
        : entries
              .map((MapEntry<int, int> entry) => entry.value)
              .reduce((int a, int b) => a > b ? a : b);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              _StatCard(
                title: 'Total vendido',
                value: '${viewModel.soldTotalTickets} bilhetes',
              ),
              if (isAdmin)
                _StatCard(
                  title: 'Valor total',
                  value: 'R\$ ${viewModel.soldTotalValue.toStringAsFixed(2)}',
                ),
            ],
          ),
          const SizedBox(height: 20),
          if (isAdmin) ...<Widget>[
            Text(
              'Vendas por vendedor',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            if (entries.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('Nenhuma venda registrada.'),
              )
            else
              SizedBox(
                height: 260,
                child: BarChart(
                  BarChartData(
                    maxY: (maxY + 1).toDouble(),
                    barTouchData: BarTouchData(enabled: true),
                    gridData: const FlGridData(show: true),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      leftTitles: const AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 28,
                        ),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (double value, TitleMeta meta) {
                            final int index = value.toInt();
                            if (index < 0 || index >= entries.length) {
                              return const SizedBox.shrink();
                            }
                            final String name = viewModel.sellerNameById(
                              entries[index].key,
                            );
                            return SideTitleWidget(
                              axisSide: meta.axisSide,
                              child: Text(
                                name,
                                style: const TextStyle(fontSize: 10),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    barGroups: entries.asMap().entries.map((
                      MapEntry<int, MapEntry<int, int>> item,
                    ) {
                      return BarChartGroupData(
                        x: item.key,
                        barRods: <BarChartRodData>[
                          BarChartRodData(
                            toY: item.value.value.toDouble(),
                            color: const Color(0xFF6EC177),
                            width: 24,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            const SizedBox(height: 20),
            ...entries.map((MapEntry<int, int> entry) {
              return Card(
                child: ListTile(
                  title: Text(viewModel.sellerNameById(entry.key)),
                  trailing: Text('${entry.value} bilhetes'),
                ),
              );
            }),
          ] else ...<Widget>[
            Text(
              'Quantidade por cliente',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            if (clientEntries.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('Nenhuma venda registrada para este vendedor.'),
              )
            else ...<Widget>[
              SizedBox(
                height: 260,
                child: PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 42,
                    sections: clientEntries.asMap().entries.map((
                      MapEntry<int, MapEntry<String, int>> item,
                    ) {
                      final Color color =
                          Colors.primaries[item.key % Colors.primaries.length];
                      return PieChartSectionData(
                        color: color,
                        value: item.value.value.toDouble(),
                        title: '${item.value.value}',
                        radius: 72,
                        titleStyle: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ...clientEntries.asMap().entries.map((
                MapEntry<int, MapEntry<String, int>> item,
              ) {
                final Color color =
                    Colors.primaries[item.key % Colors.primaries.length];
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(backgroundColor: color, radius: 8),
                    title: Text(item.value.key),
                    trailing: Text('${item.value.value} bilhete(s)'),
                  ),
                );
              }),
            ],
          ],
        ],
      ),
    );
  }
}

class _BrazilPhoneTextInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length > 11) {
      digits = digits.substring(0, 11);
    }

    final StringBuffer buffer = StringBuffer();
    if (digits.isNotEmpty) {
      buffer.write('(');
      if (digits.length <= 2) {
        buffer.write(digits);
      } else {
        buffer.write(digits.substring(0, 2));
        buffer.write(') ');
        if (digits.length <= 7) {
          buffer.write(digits.substring(2));
        } else {
          buffer.write(digits.substring(2, 7));
          buffer.write('-');
          buffer.write(digits.substring(7));
        }
      }
    }

    final String formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    _log('_StatCard.build', 'Building stat card title=$title');
    return SizedBox(
      width: 200,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 4),
              Text(value, style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
        ),
      ),
    );
  }
}
