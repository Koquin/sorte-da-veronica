import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/app_user.dart';
import '../models/ticket.dart';
import '../viewmodels/app_view_model.dart';

class HomeView extends StatelessWidget {
  const HomeView({super.key, required this.viewModel});

  final AppViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final List<Widget> tabs = <Widget>[
      _TicketsTab(viewModel: viewModel),
      _ManageTab(viewModel: viewModel),
      _StatsTab(viewModel: viewModel),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('Sorte da Veronica - ${viewModel.currentUser?.name ?? ''}'),
        actions: <Widget>[
          IconButton(
            onPressed: viewModel.isBusy ? null : viewModel.logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: tabs[viewModel.currentTab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: viewModel.currentTab,
        onDestinationSelected: viewModel.setTab,
        destinations: const <NavigationDestination>[
          NavigationDestination(icon: Icon(Icons.search), label: 'Bilhetes'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Gerenciar'),
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      widget.viewModel.searchTickets('');
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _toggleSold(Ticket ticket, bool newValue) async {
    String? buyer;
    if (newValue) {
      buyer = await _askBuyerName();
      if (buyer == null) {
        return;
      }
    }

    final bool success = await widget.viewModel.toggleTicketSold(
      ticketId: ticket.id,
      sold: newValue,
      buyerName: buyer,
    );

    if (!mounted || success) {
      return;
    }

    final String message =
        widget.viewModel.errorMessage ?? 'Erro ao atualizar bilhete.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<String?> _askBuyerName() async {
    String buyerName = '';
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Nome do comprador'),
          content: TextField(
            decoration: const InputDecoration(
              hintText: 'Digite o nome (opcional)',
            ),
            onChanged: (String value) {
              buyerName = value;
            },
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(''),
              child: const Text('Sem nome'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(buyerName),
              child: const Text('Confirmar'),
            ),
          ],
        );
      },
    );
    return name;
  }

  @override
  Widget build(BuildContext context) {
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
                onPressed: () =>
                    widget.viewModel.searchTickets(_searchController.text),
                icon: const Icon(Icons.search),
                label: const Text('Procurar'),
              ),
              const SizedBox(width: 12),
              Text('Encontrados: ${tickets.length}'),
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
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  ticket.numbers
                                      .map(widget.viewModel.formatNumber)
                                      .join(' - '),
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 8),
                                Text('Comprador: ${ticket.buyerName ?? '-'}'),
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
                                    : (bool value) => _toggleSold(ticket, value),
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

class _ManageTab extends StatefulWidget {
  const _ManageTab({required this.viewModel});

  final AppViewModel viewModel;

  @override
  State<_ManageTab> createState() => _ManageTabState();
}

class _ManageTabState extends State<_ManageTab> {
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _rangeStartController = TextEditingController();
  final TextEditingController _rangeEndController = TextEditingController();
  final TextEditingController _numbersController = TextEditingController();

  int? _selectedSellerId;

  @override
  void initState() {
    super.initState();
    final List<AppUser> sellers = widget.viewModel.sellers;
    _selectedSellerId = sellers.isEmpty ? null : sellers.first.id;
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _rangeStartController.dispose();
    _rangeEndController.dispose();
    _numbersController.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final int quantity = int.tryParse(_quantityController.text.trim()) ?? 0;
    final bool success = await widget.viewModel.generateTickets(quantity);
    if (!mounted) {
      return;
    }

    final String message = success
        ? 'Bilhetes criados com sucesso.'
        : (widget.viewModel.errorMessage ?? 'Erro ao criar bilhetes.');
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _assignByRange() async {
    if (_selectedSellerId == null) {
      return;
    }

    final int start = int.tryParse(_rangeStartController.text.trim()) ?? -1;
    final int end = int.tryParse(_rangeEndController.text.trim()) ?? -1;

    final int? updated = await widget.viewModel.assignByRange(
      start: start,
      end: end,
      sellerId: _selectedSellerId!,
    );

    if (!mounted) {
      return;
    }

    final String message = updated == null
        ? (widget.viewModel.errorMessage ?? 'Falha ao atribuir bilhetes.')
        : '$updated bilhete(s) atribuido(s) por intervalo.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _assignByNumbers() async {
    if (_selectedSellerId == null) {
      return;
    }

    final List<int> numbers = _numbersController.text
        .split(',')
        .map((String value) => int.tryParse(value.trim()))
        .whereType<int>()
        .toList();

    final int? updated = await widget.viewModel.assignByNumbers(
      numbers: numbers,
      sellerId: _selectedSellerId!,
    );

    if (!mounted) {
      return;
    }

    final String message = updated == null
        ? (widget.viewModel.errorMessage ?? 'Falha ao atribuir bilhetes.')
        : '$updated bilhete(s) atribuido(s) por numeros.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final bool admin = widget.viewModel.isAdmin;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    admin ? 'Painel administrativo' : 'Painel do vendedor',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    admin
                        ? 'Voce pode criar e atribuir bilhetes.'
                        : 'Voce tem permissao para buscar e marcar vendidos os bilhetes atribuidos a voce.',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (!admin)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'As funcoes de criacao/atribuicao sao exclusivas do admin.',
                ),
              ),
            ),
          if (admin) ...<Widget>[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Criar bilhetes aleatorios (maximo total: 100)',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Total atual: ${widget.viewModel.totalTickets} bilhete(s)',
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _quantityController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Quantidade',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: _generate,
                      child: const Text('Gerar bilhetes'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Atribuicao de bilhetes para vendedor',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      initialValue: _selectedSellerId,
                      decoration: const InputDecoration(
                        labelText: 'Vendedor',
                        border: OutlineInputBorder(),
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
                    const SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: TextField(
                            controller: _rangeStartController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'De (ex: 1)',
                              border: OutlineInputBorder(),
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
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: _assignByRange,
                      child: const Text('Atribuir por intervalo'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _numbersController,
                      decoration: const InputDecoration(
                        labelText: 'Numeros individuais (ex: 1,2,3,4)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: _assignByNumbers,
                      child: const Text('Atribuir por numeros'),
                    ),
                  ],
                ),
              ),
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
    final Map<int, int> soldBySeller = viewModel.soldBySeller;
    final List<MapEntry<int, int>> entries = soldBySeller.entries.toList()
      ..sort(
        (MapEntry<int, int> a, MapEntry<int, int> b) =>
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
              _StatCard(
                title: 'Valor total',
                value: 'R\$ ${viewModel.soldTotalValue.toStringAsFixed(2)}',
              ),
            ],
          ),
          const SizedBox(height: 20),
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
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
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
