import 'package:equatable/equatable.dart';

import 'package:submersion/core/constants/enums.dart';

/// Roles that represent professional credentials a buddy can hold.
const kProfessionalBuddyRoles = [
  BuddyRole.instructor,
  BuddyRole.diveMaster,
  BuddyRole.diveGuide,
];

/// A professional credential held by a buddy (issue #395).
class BuddyRoleCredential extends Equatable {
  final String id;
  final String buddyId;
  final BuddyRole role;
  final String? credentialNumber;
  final CertificationAgency? agency;
  final String notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  const BuddyRoleCredential({
    required this.id,
    required this.buddyId,
    required this.role,
    this.credentialNumber,
    this.agency,
    this.notes = '',
    required this.createdAt,
    required this.updatedAt,
  });

  /// Display string like "Instructor - PADI #12345".
  String get displayLabel {
    final parts = <String>[
      if (agency != null) agency!.displayName,
      if (credentialNumber != null && credentialNumber!.isNotEmpty)
        '#$credentialNumber',
    ];
    if (parts.isEmpty) return role.displayName;
    return '${role.displayName} - ${parts.join(' ')}';
  }

  BuddyRoleCredential copyWith({
    String? id,
    String? buddyId,
    BuddyRole? role,
    String? credentialNumber,
    CertificationAgency? agency,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return BuddyRoleCredential(
      id: id ?? this.id,
      buddyId: buddyId ?? this.buddyId,
      role: role ?? this.role,
      credentialNumber: credentialNumber ?? this.credentialNumber,
      agency: agency ?? this.agency,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
    id,
    buddyId,
    role,
    credentialNumber,
    agency,
    notes,
    createdAt,
    updatedAt,
  ];
}
