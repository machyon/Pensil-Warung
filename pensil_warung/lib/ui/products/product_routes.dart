import 'package:go_router/go_router.dart';

import '../../domain/product.dart';
import '../../routing/router.dart';
import 'bulk_add_screen.dart';
import 'product_detail_screen.dart';
import 'product_edit_screen.dart';

/// Sub-routes of `/produk`, drawn full screen over the tab bar.
final productRoutes = <RouteBase>[
  GoRoute(
    path: 'tambah',
    parentNavigatorKey: rootKey,
    builder: (_, s) => BulkAddScreen(firstName: s.extra is String ? s.extra! as String : null),
  ),
  GoRoute(
    path: ':id',
    parentNavigatorKey: rootKey,
    builder: (_, s) {
      final p = s.extra;
      return ProductDetailScreen(id: int.parse(s.pathParameters['id']!), initial: p is Product ? p : null);
    },
    routes: [
      GoRoute(
        path: 'ubah',
        parentNavigatorKey: rootKey,
        redirect: (_, s) => s.extra is Product ? null : '/produk',
        builder: (_, s) => ProductEditScreen(product: s.extra! as Product),
      ),
    ],
  ),
];
