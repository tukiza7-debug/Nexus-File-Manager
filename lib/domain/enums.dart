/// Shared enumerations for the entire application.
library;

enum FileCategory { folder, image, video, audio, document, archive, code, font, executable, other }

enum ViewMode { grid, list }

enum SortBy { name, size, modified, type }

enum SortDir { asc, desc }

enum ClipOp { copy, cut }

enum ConflictStrategy { ask, skip, overwrite, keepBoth, compare }

enum Edge { left, right, top, bottom }

enum ThemeBrand { nexus, win98, winxp, win7 }

enum TileBadge { dot, hatched, glyph }

extension SortByX on SortBy {
  String get label => switch (this) {
        SortBy.name => 'Name',
        SortBy.size => 'Size',
        SortBy.modified => 'Modified',
        SortBy.type => 'Type',
      };
}

extension ViewModeX on ViewMode {
  String get label => switch (this) {
        ViewMode.grid => 'Grid',
        ViewMode.list => 'List',
      };
}

extension ClipOpX on ClipOp {
  String get label => this == ClipOp.copy ? 'Copy' : 'Cut';
}

extension ThemeBrandX on ThemeBrand {
  String get label => switch (this) {
        ThemeBrand.nexus => 'Nexus',
        ThemeBrand.win98 => 'Windows 98',
        ThemeBrand.winxp => 'Windows XP',
        ThemeBrand.win7 => 'Windows 7',
      };
}
