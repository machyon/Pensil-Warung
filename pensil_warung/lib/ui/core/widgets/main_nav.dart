import 'package:material_ui/material_ui.dart';

import 'package:flutter_svg/flutter_svg.dart';

import '../theme.dart';

class NavItem {
  const NavItem(this.label, this.icon, {this.svg});
  final String label;
  final IconData icon;

  /// Design icon (24x24 viewBox, `currentColor` strokes); used instead of [icon] when set.
  final String? svg;
}

String _icon(String body) =>
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#000" '
    'stroke-width="2" stroke-linecap="round" stroke-linejoin="round">$body</svg>';

final _box = _icon('<path d="M3 7l9-4 9 4-9 4-9-4z"/><path d="M3 7v10l9 4 9-4V7"/><path d="M12 11v10"/>');
final _pencil = _icon('<path d="M4 20h4L19 9l-4-4L4 16v4z"/><path d="M14 6l4 4"/>');
final _clock = _icon('<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>');

final userNavItems = [
  NavItem('Produk', Icons.inventory_2_outlined, svg: _box),
  NavItem('Catat', Icons.edit_outlined, svg: _pencil),
  NavItem('Histori', Icons.history_rounded, svg: _clock),
];

const broadcasterNavItems = [
  NavItem('Siaran', Icons.campaign_outlined),
  NavItem('Tulis', Icons.edit_outlined),
  NavItem('Akun', Icons.person_outline_rounded),
];

Widget _icon20(NavItem item, bool on) {
  final color = on ? AppColors.onAccent : AppColors.muted;
  return item.svg == null
      ? Icon(item.icon, size: 20, color: color)
      : SvgPicture.string(item.svg!, width: 20, height: 20, colorFilter: ColorFilter.mode(color, BlendMode.srcIn));
}

/// 64 px, white, top border; the selected tab is a yellow pill with weight 800.
class MainNav extends StatelessWidget {
  const MainNav({super.key, required this.items, required this.selected, required this.onTap});

  final List<NavItem> items;
  final int selected;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: i == selected,
                    label: items[i].label,
                    child: InkWell(
                      onTap: () => onTap(i),
                      child: Center(
                        child: Container(
                          height: 44,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: i == selected ? AppColors.accent : null,
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _icon20(items[i], i == selected),
                              const SizedBox(width: 6),
                              Text(
                                items[i].label,
                                style: appText(13,
                                    weight: i == selected ? FontWeight.w800 : FontWeight.w600,
                                    color: i == selected ? AppColors.onAccent : AppColors.muted),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
