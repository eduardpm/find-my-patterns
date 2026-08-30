import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/api_client.dart';
import '../network/network_providers.dart';
import '../settings/settings.dart';
import '../settings/settings_controller.dart';

/// Where the user types the address of their server.
///
/// Shared by the Settings screen and the login screen, so that an app which has
/// never been configured can be configured from wherever the user first lands.
/// Saving validates first: a bad host or port is refused with a reason rather
/// than silently becoming a default.
class ServerForm extends ConsumerStatefulWidget {
  /// Creates the server form.
  const ServerForm({super.key, this.onSaved});

  /// Called after an address has been validated and stored.
  final VoidCallback? onSaved;

  @override
  ConsumerState<ServerForm> createState() => _ServerFormState();
}

class _ServerFormState extends ConsumerState<ServerForm> {
  final TextEditingController _host = TextEditingController();
  final TextEditingController _port = TextEditingController();
  BackendScheme _scheme = BackendScheme.http;
  String? _error;
  String? _testResult;
  bool _testFailed = false;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _adoptStoredAddress(
      ref.read(settingsProvider).value?.backend ?? BackendAddress.unset,
    );
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  /// Fills the fields from [backend], leaving anything the user has typed since
  /// the last save untouched only when the stored value has not changed.
  void _adoptStoredAddress(BackendAddress backend) {
    _scheme = backend.scheme;
    _host.text = backend.host;
    _port.text = backend.port.toString();
  }

  Future<void> _save() async {
    final result = await ref
        .read(settingsProvider.notifier)
        .saveBackendAddress(
          rawHost: _host.text,
          rawPort: _port.text,
          scheme: _scheme,
        );
    if (!mounted) return;
    switch (result) {
      case BackendAddressAccepted(:final address):
        setState(() {
          _error = null;
          _adoptStoredAddress(address);
        });
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(const SnackBar(content: Text('Server saved')));
        widget.onSaved?.call();
      case BackendAddressRejected(:final message):
        setState(() => _error = message);
    }
  }

  Future<void> _test() async {
    final result = BackendAddress.parse(
      rawHost: _host.text,
      rawPort: _port.text,
      scheme: _scheme,
    );
    if (result case BackendAddressRejected(:final message)) {
      setState(() => _error = message);
      return;
    }
    final address = (result as BackendAddressAccepted).address;
    setState(() {
      _error = null;
      _testing = true;
      _testResult = null;
    });
    final ConnectionResult outcome = await ref
        .read(apiClientProvider)
        .testConnection(address);
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResult = outcome.detail;
      _testFailed = !outcome.ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Keep the fields honest if the stored address changes underneath this form
    // — another screen saving, or the initial load landing after the first
    // build. Without this the form can show a stale address indefinitely.
    ref.listen(settingsProvider, (previous, next) {
      final before = previous?.value?.backend;
      final after = next.value?.backend;
      if (after != null && after != before) {
        setState(() => _adoptStoredAddress(after));
      }
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<BackendScheme>(
          // No selected-check icon: Material reserves room for one inside
          // each segment, and at 320dp/2x that left "HTTP" 106px of the
          // 112px it needs, so the label broke mid-word to "HTT"/"P" (found
          // by `test/screen_layout_matrix_test.dart`). Nothing overflowed
          // and nothing threw. The segment's own fill already shows which
          // scheme is selected, so the icon was carrying no information the
          // control did not already convey.
          showSelectedIcon: false,
          segments: [
            for (final scheme in BackendScheme.values)
              ButtonSegment(value: scheme, label: Text(scheme.label)),
          ],
          selected: {_scheme},
          onSelectionChanged: (selection) =>
              setState(() => _scheme = selection.first),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _host,
          autocorrect: false,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Host',
            hintText: '192.168.1.20 or 10.0.2.2',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _port,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Port',
            border: OutlineInputBorder(),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          _Message(text: _error!, ok: false),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            FilledButton(onPressed: _save, child: const Text('Save')),
            OutlinedButton(
              onPressed: _testing ? null : _test,
              child: _testing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Test connection'),
            ),
          ],
        ),
        if (_testResult != null) ...[
          const SizedBox(height: 12),
          _Message(text: _testResult!, ok: !_testFailed),
        ],
      ],
    );
  }
}

/// A success or failure line.
///
/// Article 11 of the constitution: nothing depends on colour alone, so the
/// icon and the screen-reader label carry the outcome too.
class _Message extends StatelessWidget {
  const _Message({required this.text, required this.ok});

  final String text;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = ok ? theme.colorScheme.primary : theme.colorScheme.error;
    return Semantics(
      liveRegion: true,
      label: ok ? 'Success: $text' : 'Problem: $text',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ok ? Icons.check_circle_outline : Icons.error_outline,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(color: color)),
          ),
        ],
      ),
    );
  }
}
