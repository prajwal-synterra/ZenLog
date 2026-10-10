import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/zen_colors.dart';
import '../../services/api_service.dart';
import '../../state/zen_state.dart';

class MyProductsScreen extends StatefulWidget {
  final ZenState state;

  const MyProductsScreen({super.key, required this.state});

  static Future<void> push(BuildContext context, ZenState state) {
    return Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MyProductsScreen(state: state)),
    );
  }

  @override
  State<MyProductsScreen> createState() => _MyProductsScreenState();
}

class _MyProductsScreenState extends State<MyProductsScreen> {
  final ApiService _api = ApiService();
  final TextEditingController _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _products = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProducts({String? query}) async {
    setState(() => _isLoading = true);
    final list = await _api.getProducts(q: query);
    if (mounted) {
      setState(() {
        _products = list;
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteProduct(String id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) {
        final t = context.zen;
        return AlertDialog(
          backgroundColor: t.surface,
          title: Text('Delete $name?', style: TextStyle(color: t.ink)),
          content: Text('Remove this product from your saved library?', style: TextStyle(color: t.inkMuted)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dlgCtx, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(dlgCtx, true),
              style: ElevatedButton.styleFrom(backgroundColor: t.dangerFill, foregroundColor: Colors.white),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      final ok = await _api.deleteProduct(id);
      if (ok && mounted) {
        HapticFeedback.lightImpact();
        _loadProducts(query: _searchCtrl.text.trim());
      }
    }
  }

  void _showPortionLogSheet(Map<String, dynamic> product) {
    final t = context.zen;
    final productId = product['id'] as String? ?? product['_id'] as String? ?? '';
    final name = product['name'] as String? ?? 'Product';
    final servingSizeG = (product['serving_size_g'] as num?)?.toDouble() ?? 100.0;
    final per100 = (product['per_100g'] as Map?) ?? {};
    final prot100 = (per100['protein_g'] as num?)?.toDouble() ?? 0.0;
    final cal100 = (per100['energy_kcal'] as num?)?.toDouble() ?? 0.0;

    double servings = 1.0;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final portionGrams = servingSizeG * servings;
            final portionProt = (prot100 * portionGrams) / 100.0;
            final portionCal = ((cal100 * portionGrams) / 100.0).round();

            return Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(color: t.line, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    name,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, color: t.ink),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${portionGrams.toStringAsFixed(0)}g  ·  ${portionProt.toStringAsFixed(1)}g protein  ·  $portionCal kcal',
                    style: TextStyle(fontSize: 13, color: t.inkMuted),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, size: 28),
                        onPressed: servings > 0.5
                            ? () {
                                setSheetState(() {
                                  servings = (servings - 0.5).clamp(0.5, 10.0);
                                });
                              }
                            : null,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          '${servings.toStringAsFixed(1)} servings',
                          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: t.ink),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline, size: 28),
                        onPressed: () {
                          setSheetState(() {
                            servings = (servings + 0.5).clamp(0.5, 10.0);
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(sheetCtx);
                        final ok = await widget.state.logProduct(
                          productId,
                          servings: servings,
                        );
                        if (mounted) {
                          if (ok) {
                            HapticFeedback.mediumImpact();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Logged ${servings.toStringAsFixed(1)} serv of $name!'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: t.ink,
                        foregroundColor: t.onInk,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        'Log to Today (${portionProt.toStringAsFixed(0)}g protein)',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.zen;

    return Scaffold(
      backgroundColor: t.surface,
      appBar: AppBar(
        backgroundColor: t.surface,
        elevation: 0,
        title: Text(
          'My Saved Products',
          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: t.ink),
        ),
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (val) => _loadProducts(query: val.trim()),
              decoration: InputDecoration(
                hintText: 'Search products or brands…',
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true,
                fillColor: t.surfaceAlt,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: t.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: t.line),
                ),
              ),
            ),
          ),

          Expanded(
            child: _isLoading
                ? Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 2, color: t.accent),
                    ),
                  )
                : _products.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.bookmark_border_rounded, size: 48, color: t.inkFaint),
                              const SizedBox(height: 12),
                              Text(
                                'No saved products yet',
                                style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: t.ink),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Scan a packaged food label and tap the bookmark icon to save it here for instant logging.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 13, color: t.inkMuted),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _products.length,
                        itemBuilder: (ctx, i) {
                          final p = _products[i];
                          final id = p['id'] as String? ?? p['_id'] as String? ?? '';
                          final name = p['name'] as String? ?? 'Product';
                          final brand = p['brand'] as String?;
                          final per100 = (p['per_100g'] as Map?) ?? {};
                          final prot = (per100['protein_g'] as num?)?.toDouble() ?? 0.0;
                          final cal = (per100['energy_kcal'] as num?)?.toInt() ?? 0;
                          final servingSizeG = (p['serving_size_g'] as num?)?.toInt() ?? 100;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: t.surfaceAlt,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: t.line),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                              title: Text(
                                name,
                                style: GoogleFonts.inter(fontSize: 14.5, fontWeight: FontWeight.w600, color: t.ink),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (brand != null && brand.isNotEmpty)
                                    Text(brand, style: TextStyle(fontSize: 12, color: t.inkMuted)),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${prot.toStringAsFixed(1)}g protein · $cal kcal / 100g (Serving: ${servingSizeG}g)',
                                    style: TextStyle(fontSize: 12, color: t.successText, fontWeight: FontWeight.w500),
                                  ),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(Icons.add_circle_outline, color: t.ink),
                                    tooltip: 'Log',
                                    onPressed: () => _showPortionLogSheet(p),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.delete_outline, size: 20, color: t.dangerFill),
                                    tooltip: 'Delete',
                                    onPressed: () => _deleteProduct(id, name),
                                  ),
                                ],
                              ),
                              onTap: () => _showPortionLogSheet(p),
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
