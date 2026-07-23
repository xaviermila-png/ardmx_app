import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/protocol/virtuino_update.dart';
import '../../routing/app_router.dart';
import '../../state/providers.dart';
import '../../widgets/app_scaffold.dart';

/// ARDMX One's own "Paràmetres" screen — reached from [ArdmxOneScreen] via a
/// button between the back arrow and the exit button. Kept separate from
/// ARDMX4's Parameters screen: different device, different fields.
///
/// Only "Nombre de canals actius" for now (wire index V08 — see
/// `firmware/ardmx_one/src/main.cpp`); more fields will be added here as the
/// firmware grows to support them. The Bluetooth name change and factory
/// reset live one level deeper, in the "Configuració del sistema" screen —
/// deliberately not on this screen, so a user browsing normal settings can't
/// stumble into either by accident (both require real recovery steps:
/// re-pairing after a rename, losing the current scene after a reset).
class ArdmxOneConfigScreen extends ConsumerStatefulWidget {
  const ArdmxOneConfigScreen({super.key});

  @override
  ConsumerState<ArdmxOneConfigScreen> createState() =>
      _ArdmxOneConfigScreenState();
}

class _ArdmxOneConfigScreenState extends ConsumerState<ArdmxOneConfigScreen> {
  static const _numeroCanalsVIndex = 8;

  final _numeroCanalsController = TextEditingController();
  StreamSubscription<VirtuinoUpdate>? _subscription;
  String? _numeroCanalsError;

  @override
  void initState() {
    super.initState();
    _subscription = ref.read(protocolProvider).updates.listen((update) {
      if (update is VirtuinoVUpdate && update.index == _numeroCanalsVIndex) {
        setState(() {
          _numeroCanalsController.text = update.value.round().toString();
          _numeroCanalsError = null;
        });
      }
    });
    ref.read(protocolProvider).requestV(_numeroCanalsVIndex);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _numeroCanalsController.dispose();
    super.dispose();
  }

  // El firmware exigeix que numeroCanals sigui sempre múltiple de 3 (cada
  // slider en controla un grup de 3) — en lloc de corregir-ho en silenci,
  // avisem i no enviem res fins que l'usuari ho arregli. Retorna el valor
  // vàlid, o null si l'entrada actual encara no ho és.
  int? _validate(String raw) {
    final value = int.tryParse(raw);
    if (value == null || value < 1 || value > 512 || value % 3 != 0) {
      setState(() {
        _numeroCanalsError =
            'Ha de ser un múltiple de 3, entre 1 i 512 (p.ex. 48, 51, 54...)';
      });
      return null;
    }
    setState(() => _numeroCanalsError = null);
    return value;
  }

  // Es crida en cada pulsació — només actualitza l'error en directe (no
  // envia res encara). Sense això, si l'usuari corregeix el número i després
  // tanca el teclat amb el gest "enrere" d'Android en lloc de tocar fora del
  // camp o prémer "Fet", `onTapOutside`/`onSubmitted` mai arriben a disparar-
  // se i l'error queda enganxat encara que el valor ja sigui correcte.
  void _onChanged(String raw) => _validate(raw);

  // Es crida en perdre el focus (tocar fora del camp o prémer "Fet" al
  // teclat) — és quan realment s'envia el valor a l'ARDMX One, no a cada
  // tecla, per no inundar el protocol amb escriptures intermèdies mentre
  // s'escriu un número de diverses xifres.
  void _submit(String raw) {
    final value = _validate(raw);
    if (value != null) {
      ref.read(protocolProvider).writeV(_numeroCanalsVIndex, value);
    }
  }

  // Flotant i amb marge inferior perquè no quedi tapat pel propi botó de
  // fletxa enrere (56px d'alçada + 12px de padding, vegeu el Padding que
  // l'envolta més avall).
  void _showBackBlockedMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(bottom: 90, left: 16, right: 16),
        content: Text('Corregeix el nombre de canals abans de tornar enrere.'),
      ),
    );
  }

  // Sortir d'aquesta pantalla (fletxa pròpia o gest/botó enrere del
  // sistema) és l'única manera fiable de saber que l'usuari ha acabat
  // d'editar — per això sempre es crida _submit() aquí abans de decidir si
  // es pot sortir, en lloc de confiar només en onSubmitted/onTapOutside del
  // camp (que mai arriben a disparar-se si es surt amb el gest enrere
  // d'Android, deixant el valor escrit sense enviar mai al dispositiu).
  void _attemptBack() {
    _submit(_numeroCanalsController.text);
    if (_numeroCanalsError != null) {
      _showBackBlockedMessage();
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // canPop sempre fals: tota la decisió (confirmar el valor i, si és
      // vàlid, sortir) es delega a _attemptBack() des d'aquí baix, perquè
      // el gest/botó enrere del sistema faci exactament el mateix que la
      // fletxa pròpia.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _attemptBack();
      },
      child: AppScaffold(
        title: 'Paràmetres',
        automaticallyImplyLeading: false,
        body: Column(
          children: [
            // Al capdamunt (no centrada verticalment): quan s'hi afegeixin
            // més opcions de configuració, aniran seguint aquesta mateixa,
            // de dalt a baix.
            Padding(
              padding: const EdgeInsets.all(16),
              child: _Section(
                title: 'Nombre de canals actius',
                child: Column(
                  children: [
                    const Text(
                      'Màxim: 512 canals',
                      style: TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 90,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.shade600,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: TextField(
                        controller: _numeroCanalsController,
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onChanged: _onChanged,
                        onSubmitted: _submit,
                        onTapOutside: (_) {
                          FocusManager.instance.primaryFocus?.unfocus();
                          _submit(_numeroCanalsController.text);
                        },
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '(ha de ser múltiple de 3)',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13),
                    ),
                    if (_numeroCanalsError != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        _numeroCanalsError!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12, color: Colors.red),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const Expanded(child: SizedBox()),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  FloatingActionButton(
                    heroTag: 'ardmxOneConfigBack',
                    onPressed: _attemptBack,
                    tooltip: 'Tornar als canals',
                    child: const Icon(Icons.arrow_back),
                  ),
                  FloatingActionButton(
                    heroTag: 'ardmxOneSystemConfig',
                    onPressed: () {
                      _submit(_numeroCanalsController.text);
                      if (_numeroCanalsError != null) {
                        _showBackBlockedMessage();
                        return;
                      }
                      Navigator.of(
                        context,
                      ).pushNamed(AppRoutes.ardmxOneSystemConfig);
                    },
                    tooltip: 'Configuració del sistema',
                    child: const Icon(Icons.build),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Same card look as ARDMX4's Parameters screen (`_Section` there) — grey
/// rounded box with a bold centered title — kept as its own private copy
/// here rather than shared, since these two screens' widgets are otherwise
/// deliberately independent (see the class doc up top). Also reused by
/// `ArdmxOneSystemConfigScreen` via its own private copy, for the same
/// reason.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
