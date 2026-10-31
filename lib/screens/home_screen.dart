import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../data/db.dart';
import '../data/demo_sales.dart';
import '../data/sales.dart';
import '../ml/embedder.dart';
import '../ml/models.dart';
import '../ui/format.dart';
import '../ui/theme.dart';
import 'receipt_screen.dart';
import 'shop_dialog.dart';

/// Earnings dashboard (layout from the Ginlo mock-ups): store, total sales with chart, top item,
/// sales breakdown and recent sales. Reloads whenever a sale is saved.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Period _period = Period.daily;

  Future<({SalesStats stats, ({String name, String upiId}) shop, Uint8List? topPhoto})> _load() async {
    final db = await AppDb.open();
    final now = DateTime.now();
    final r = periodRange(_period, now);
    final stats = SalesStats.compute(_period, now, await db.sales(r.from, r.to), await db.sales(r.prevFrom, r.from));
    final top = stats.topItem;
    final photo = top == null ? null : await db.productPhoto(top.name, embedderSpecs[Models.billEmbedder].id);
    return (stats: stats, shop: await db.shop(), topPhoto: photo);
  }

  Future<void> _pickPeriod() async {
    var choice = _period;
    final picked = await showModalBottomSheet<Period>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text('Select Period', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                    ),
                    IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                  ],
                ),
                for (final p in Period.values)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Material(
                      color: p == choice ? GinloColors.blueSoft : GinloColors.background,
                      borderRadius: BorderRadius.circular(16),
                      child: ListTile(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        leading: Icon(
                          p == Period.lifetime ? Icons.all_inclusive : Icons.calendar_month,
                          color: p == choice ? GinloColors.blue : GinloColors.ink,
                        ),
                        title: Text(
                          p.label,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: p == choice ? GinloColors.blue : GinloColors.ink,
                          ),
                        ),
                        trailing: Icon(
                          p == choice ? Icons.radio_button_checked : Icons.radio_button_off,
                          color: p == choice ? GinloColors.blue : GinloColors.muted,
                        ),
                        onTap: () => setSheet(() => choice = p),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                FilledButton(onPressed: () => Navigator.pop(ctx, choice), child: const Text('Apply')),
              ],
            ),
          ),
        ),
      ),
    );
    if (picked != null) setState(() => _period = picked);
  }

  Future<void> _addDemoSales() async {
    final db = await AppDb.open();
    final products = await db.products();
    final sales = demoSales(products, DateTime.now());
    await db.insertSales(sales);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            products.isEmpty
                ? 'Teach a product first: demo sales use your products'
                : 'Added ${sales.length} demo bills for ${products.length} products',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GinloHeader(),
      body: ValueListenableBuilder(
        valueListenable: AppDb.changes, // a new sale or store edit refreshes the dashboard
        builder: (context, _, _) => FutureBuilder(
          future: _load(),
          builder: (context, snap) {
            if (snap.hasError) return Center(child: Text('${snap.error}'));
            final d = snap.data;
            if (d == null) return const Center(child: CircularProgressIndicator());
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                _StoreCard(name: d.shop.name, upiId: d.shop.upiId),
                const SizedBox(height: 12),
                _TotalSalesCard(stats: d.stats, period: _period, onPickPeriod: _pickPeriod),
                const SizedBox(height: 12),
                if (d.stats.topItem != null) ...[
                  _TopItemCard(top: d.stats.topItem!, photo: d.topPhoto),
                  const SizedBox(height: 12),
                ],
                if (d.stats.bills > 0) ...[
                  _BreakdownCard(stats: d.stats),
                  const SizedBox(height: 12),
                  _RecentSalesCard(sales: d.stats.recent),
                ] else
                  GinloCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'No sales in this period yet. Bills you mark as paid show up here.',
                          style: TextStyle(color: GinloColors.muted),
                        ),
                        const SizedBox(height: 8),
                        // For demos: a month of made-up bills for the products you've taught.
                        OutlinedButton.icon(
                          onPressed: _addDemoSales,
                          icon: const Icon(Icons.auto_graph),
                          label: const Text('Add demo sales (30 days)'),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Soft blue circle with an icon, used on several cards.
Widget _iconBubble(IconData icon) => Container(
  width: 48,
  height: 48,
  decoration: const BoxDecoration(color: GinloColors.blueSoft, shape: BoxShape.circle),
  child: Icon(icon, color: GinloColors.blue),
);

class _StoreCard extends StatelessWidget {
  const _StoreCard({required this.name, required this.upiId});
  final String name, upiId;

  @override
  Widget build(BuildContext context) {
    return GinloCard(
      child: Row(
        children: [
          _iconBubble(Icons.storefront),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                InkWell(
                  onTap: upiId.isEmpty
                      ? null
                      : () {
                          Clipboard.setData(ClipboardData(text: upiId));
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('UPI ID copied')));
                        },
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          upiId.isEmpty ? 'Add your UPI ID' : upiId,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: GinloColors.muted),
                        ),
                      ),
                      if (upiId.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.copy, size: 16, color: GinloColors.muted),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              backgroundColor: GinloColors.blueSoft,
              foregroundColor: GinloColors.blue,
              minimumSize: const Size(48, 40),
            ),
            onPressed: () => showShopDialog(context),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Edit'),
          ),
        ],
      ),
    );
  }
}

class _TotalSalesCard extends StatelessWidget {
  const _TotalSalesCard({required this.stats, required this.period, required this.onPickPeriod});
  final SalesStats stats;
  final Period period;
  final VoidCallback onPickPeriod;

  @override
  Widget build(BuildContext context) {
    final change = stats.changePct;
    return GinloCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Total Sales', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              ActionChip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [Text(period.label), const Icon(Icons.expand_more, size: 18)],
                ),
                onPressed: onPickPeriod,
                backgroundColor: GinloColors.background,
                side: BorderSide.none,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ],
          ),
          Text(inr(stats.total), style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800)),
          if (change != null)
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${change >= 0 ? '↑' : '↓'} ${pct(change)} ',
                    style: TextStyle(
                      color: change >= 0 ? GinloColors.up : GinloColors.down,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(
                    text: period.comparedTo,
                    style: const TextStyle(color: GinloColors.muted),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          SizedBox(height: 150, child: period == Period.monthly ? _line(stats) : _bars(stats)),
        ],
      ),
    );
  }

  /// Bars (today by 2 hours, lifetime by month). Labels on every other bar so they fit.
  Widget _bars(SalesStats s) {
    final maxY = s.buckets.fold(0.0, (m, b) => math.max(m, b.amount));
    return BarChart(
      BarChartData(
        maxY: maxY == 0 ? 1 : maxY * 1.15,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(enabled: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          topTitles: const AxisTitles(),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              getTitlesWidget: (v, meta) => SideTitleWidget(
                meta: meta,
                child: Text(
                  v.toInt().isEven ? s.buckets[v.toInt()].label : '',
                  style: const TextStyle(fontSize: 10, color: GinloColors.muted),
                ),
              ),
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < s.buckets.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: s.buckets[i].amount,
                  width: 10,
                  color: GinloColors.blue,
                  borderRadius: BorderRadius.circular(6),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// This month: smooth line with a soft fill, like the "Monthly" mock-up.
  Widget _line(SalesStats s) {
    final n = s.buckets.length;
    return LineChart(
      LineChartData(
        minY: 0,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          topTitles: const AxisTitles(),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: 7,
              getTitlesWidget: (v, meta) => SideTitleWidget(
                meta: meta,
                child: Text(
                  s.buckets[v.toInt().clamp(0, n - 1)].label,
                  style: const TextStyle(fontSize: 10, color: GinloColors.muted),
                ),
              ),
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [for (var i = 0; i < n; i++) FlSpot(i.toDouble(), s.buckets[i].amount)],
            isCurved: true,
            preventCurveOverShooting: true,
            color: GinloColors.blue,
            barWidth: 3,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [GinloColors.blue.withValues(alpha: 0.25), GinloColors.blue.withValues(alpha: 0.02)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopItemCard extends StatelessWidget {
  const _TopItemCard({required this.top, required this.photo});
  final ({String name, int qty, double? changePct}) top;
  final Uint8List? photo;

  @override
  Widget build(BuildContext context) {
    final change = top.changePct;
    return GinloCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Top Performing Item', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: photo == null
                    ? Container(
                        width: 52,
                        height: 52,
                        color: GinloColors.yellow.withValues(alpha: 0.3),
                        child: const Icon(Icons.inventory_2),
                      )
                    : Image.memory(photo!, width: 52, height: 52, fit: BoxFit.cover),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(top.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    Text('${top.qty} sold', style: const TextStyle(color: GinloColors.muted)),
                  ],
                ),
              ),
              if (change != null)
                Text(
                  '${change >= 0 ? '↑' : '↓'} ${change.abs().toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: change >= 0 ? GinloColors.up : GinloColors.down,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BreakdownCard extends StatefulWidget {
  const _BreakdownCard({required this.stats});
  final SalesStats stats;

  @override
  State<_BreakdownCard> createState() => _BreakdownCardState();
}

class _BreakdownCardState extends State<_BreakdownCard> {
  bool _byPayment = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.stats;
    // Items: share of units sold (top 4 + Others). Payment: share of money.
    final Map<String, double> raw = _byPayment
        ? s.byPayment
        : {for (final e in s.itemsByName.entries) e.key: e.value.toDouble()};
    final sorted = raw.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final slices = <MapEntry<String, double>>[...sorted.take(4)];
    final rest = sorted.skip(4).fold(0.0, (t, e) => t + e.value);
    if (rest > 0) slices.add(MapEntry('Others', rest));
    final sum = slices.fold(0.0, (t, e) => t + e.value);

    Widget tab(String label, bool selected, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        showCheckmark: false,
        selectedColor: GinloColors.blue,
        backgroundColor: GinloColors.background,
        side: BorderSide.none,
        labelStyle: TextStyle(color: selected ? Colors.white : GinloColors.ink, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    return GinloCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Sales Breakdown', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: [
              tab('Items', !_byPayment, () => setState(() => _byPayment = false)),
              tab('Payment Method', _byPayment, () => setState(() => _byPayment = true)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(
                width: 140,
                height: 140,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PieChart(
                      PieChartData(
                        centerSpaceRadius: 46,
                        sectionsSpace: 2,
                        startDegreeOffset: -90,
                        sections: [
                          for (var i = 0; i < slices.length; i++)
                            PieChartSectionData(
                              value: slices[i].value,
                              color: GinloColors.chart[i % GinloColors.chart.length],
                              radius: 20,
                              showTitle: false,
                            ),
                        ],
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${_byPayment ? s.bills : s.itemsSold}',
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                        ),
                        Text(
                          _byPayment ? 'bills' : 'items sold',
                          style: const TextStyle(fontSize: 12, color: GinloColors.muted),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  children: [
                    for (var i = 0; i < slices.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            CircleAvatar(radius: 6, backgroundColor: GinloColors.chart[i % GinloColors.chart.length]),
                            const SizedBox(width: 8),
                            Expanded(child: Text(slices[i].key, overflow: TextOverflow.ellipsis)),
                            Text('${(slices[i].value / sum * 100).round()}%'),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecentSalesCard extends StatelessWidget {
  const _RecentSalesCard({required this.sales});
  final List<Sale> sales;

  @override
  Widget build(BuildContext context) {
    return GinloCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Recent Sales', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          for (final s in sales)
            ListTile(
              contentPadding: EdgeInsets.zero,
              // Opens the bill's invoice (share as PDF from there).
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => ReceiptScreen(sale: s, fromHistory: true)),
              ),
              leading: _iconBubble(s.payment == 'Cash' ? Icons.payments_outlined : Icons.qr_code_2),
              title: Text(
                s.lines.isEmpty
                    ? 'Bill'
                    : s.lines.length == 1
                    ? s.lines.first.name
                    : '${s.lines.first.name} +${s.lines.length - 1}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text('${s.lines.fold(0, (n, l) => n + l.qty)} pcs · ${s.payment}'),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(inr(s.total), style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(clock(s.time), style: const TextStyle(fontSize: 12, color: GinloColors.muted)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
