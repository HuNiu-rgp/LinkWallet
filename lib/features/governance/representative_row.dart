import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../shared/theme_context.dart';
import '../../shared/formatters.dart';

class RepresentativeRow extends StatelessWidget {
  final String address, name, networkVotes, originalVotes, allocatedVotes;
  final VoidCallback? onEdit;
  const RepresentativeRow({
    super.key,
    required this.address,
    required this.name,
    required this.networkVotes,
    required this.originalVotes,
    required this.allocatedVotes,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 12),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: context.palette.border)),
    ),
    child: Row(
      children: [
        Icon(
          LucideIcons.landmark,
          size: 18,
          color: context.palette.mutedForeground,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              Tooltip(
                message: address,
                child: Text(
                  short(address),
                  style: TextStyle(
                    fontSize: 11,
                    color: context.palette.mutedForeground,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        if (MediaQuery.sizeOf(context).width >= 1100) ...[
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('全网票数 $networkVotes', style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 5),
              Text(
                '链上已投 $originalVotes',
                style: TextStyle(
                  fontSize: 11,
                  color: context.palette.mutedForeground,
                ),
              ),
            ],
          ),
          const SizedBox(width: 20),
        ],
        Tooltip(
          message: '全网票数 $networkVotes · 链上已投 $originalVotes',
          child: ShadButton.outline(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            onPressed: onEdit,
            child: Text('分配 $allocatedVotes 票'),
          ),
        ),
      ],
    ),
  );
}
