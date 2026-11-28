import 'package:material_ui/material_ui.dart';

import '../theme.dart';

class NavItem {
  const NavItem(this.label, this.icon);
  final String label;
  final IconData icon;
}

const userNavItems = [
  NavItem('Produk', Icons.inventory_2_outlined),
  NavItem('Catat', Icons.edit_note_rounded),
  NavItem('Histori', Icons.history_rounded),
];

const broadcasterNavItems = [
  NavItem('Siaran', Icons.campaign_outlined),
  NavItem('Tulis', Icons.edit_outlined),
  NavItem('Akun', Icons.person_outline_rounded),
];

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
                              Icon(items[i].icon, size: 22, color: i == selected ? AppColors.onAccent : AppColors.muted),
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
