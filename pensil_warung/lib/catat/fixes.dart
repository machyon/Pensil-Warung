import 'parser.dart';
import 'result.dart';

List<Fix> notFoundFixes(int lineNo, Parsed p, String? suggestion) => const [];
List<Fix> stockFixes(int lineNo, Parsed p, String name, int stock, int missing) => const [];
List<Fix> adjustFixes(int lineNo, Parsed p, int stock) => const [];
