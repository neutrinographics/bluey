import 'package:bluey/src/features/connection/domain/connection_state.dart';
import 'package:bluey/src/features/connection/domain/link.dart';
import 'package:bluey/src/features/connection/domain/link_end.dart';
import 'package:bluey/src/features/connection/domain/link_id.dart';
import 'package:bluey/src/features/connection/domain/link_input.dart';
import 'package:bluey/src/shared/domain/device_address.dart';
import 'package:flutter_test/flutter_test.dart';

const id = LinkId('L1');
const device = DeviceAddress('AA:BB:CC:DD:EE:01');

Link after(List<LinkInput> inputs) => inputs.fold(
  const Link.opened(id: id, device: device),
  (link, input) => link.on(input).link,
);

const discovered = ServicesDiscovered();
const request = DisconnectRequested();
const radioClosing = RadioReported(LinkReport.disconnecting);
const radioGone = RadioReported(LinkReport.disconnected);

void main() {
  group('the lifecycle table', () {
    // (name, inputs so far, input, state after, duty, end after)
    final rows = <
      (String, List<LinkInput>, LinkInput, ConnectionState, LinkDuty?, LinkEnd?)
    >[
      (
        'discovery makes a linked link ready',
        [],
        discovered,
        ConnectionState.ready,
        null,
        null,
      ),
      (
        'a repeated connected report never takes ready back to linked',
        [discovered],
        const RadioReported(LinkReport.connected),
        ConnectionState.ready,
        null,
        null,
      ),
      (
        'a connecting report changes nothing',
        [],
        const RadioReported(LinkReport.connecting),
        ConnectionState.linked,
        null,
        null,
      ),
      (
        'the radio closing the link',
        [discovered],
        radioClosing,
        ConnectionState.disconnecting,
        null,
        null,
      ),
      (
        'a request asks for the close',
        [discovered],
        request,
        ConnectionState.disconnecting,
        LinkDuty.closeTheLink,
        null,
      ),
      (
        'a second request joins the close in flight',
        [request],
        request,
        ConnectionState.disconnecting,
        null,
        null,
      ),
      (
        'a request while the radio is closing asks for the close',
        [radioClosing],
        request,
        ConnectionState.disconnecting,
        LinkDuty.closeTheLink,
        null,
      ),
      (
        'a confirmed close ends on request',
        [request],
        const CloseConfirmed(),
        ConnectionState.disconnected,
        LinkDuty.releaseAndAnnounce,
        const EndedOnRequest(),
      ),
      (
        'a disconnected report ends a requested close on request',
        [request],
        radioGone,
        ConnectionState.disconnected,
        LinkDuty.releaseAndAnnounce,
        const EndedOnRequest(),
      ),
      (
        'reports ending ends a requested close on request',
        [request],
        const ReportsEnded(),
        ConnectionState.disconnected,
        LinkDuty.releaseAndAnnounce,
        const EndedOnRequest(),
      ),
      (
        'the radio finishing its own close is a drop',
        [radioClosing],
        radioGone,
        ConnectionState.disconnected,
        LinkDuty.releaseAndAnnounce,
        const EndedByDrop(),
      ),
      (
        'a failed close returns to ready',
        [discovered, request],
        const CloseFailed(),
        ConnectionState.ready,
        null,
        null,
      ),
      (
        'a failed close returns to linked',
        [request],
        const CloseFailed(),
        ConnectionState.linked,
        null,
        null,
      ),
      (
        'a drop ends a linked link',
        [],
        radioGone,
        ConnectionState.disconnected,
        LinkDuty.releaseAndAnnounce,
        const EndedByDrop(),
      ),
      (
        'reports ending is a drop',
        [discovered],
        const ReportsEnded(),
        ConnectionState.disconnected,
        LinkDuty.releaseAndAnnounce,
        const EndedByDrop(),
      ),
      (
        'an outage invalidates an up link',
        [discovered],
        const RadioOutageBegan(RadioOutage.off),
        ConnectionState.invalidated,
        LinkDuty.releaseAndAnnounce,
        const EndedByRadioOutage(RadioOutage.off),
      ),
      (
        'an outage invalidates a closing link',
        [request],
        const RadioOutageBegan(RadioOutage.unknown),
        ConnectionState.invalidated,
        LinkDuty.releaseAndAnnounce,
        const EndedByRadioOutage(RadioOutage.unknown),
      ),
      (
        'a stray close answer changes nothing',
        [discovered],
        const CloseConfirmed(),
        ConnectionState.ready,
        null,
        null,
      ),
      (
        'discovery while closing changes nothing',
        [request],
        discovered,
        ConnectionState.disconnecting,
        null,
        null,
      ),
    ];

    for (final (name, before, input, state, duty, end) in rows) {
      test(name, () {
        // arrange
        final link = after(before);

        // act
        final step = link.on(input);

        // assert
        expect(step.link.state, state);
        expect(step.duty, duty);
        expect(step.link.end, end);
      });
    }
  });

  group('the cases the table leaves to the builder', () {
    // (name, inputs so far, input, state after, duty, end in sight after)
    final rows = <
      (String, List<LinkInput>, LinkInput, ConnectionState, LinkDuty?, LinkEnd?)
    >[
      (
        'a stray close failure on an up link changes nothing',
        [discovered],
        const CloseFailed(),
        ConnectionState.ready,
        null,
        null,
      ),
      (
        'a close the radio ends before it is asked is not answered',
        [radioClosing],
        const CloseConfirmed(),
        ConnectionState.disconnecting,
        null,
        const EndedByDrop(),
      ),
      (
        'a close failure the radio was not asked for changes nothing',
        [radioClosing],
        const CloseFailed(),
        ConnectionState.disconnecting,
        null,
        const EndedByDrop(),
      ),
      (
        'a failed close while the radio is closing stays closing, '
            'heading for a drop',
        [discovered, radioClosing, request],
        const CloseFailed(),
        ConnectionState.disconnecting,
        null,
        const EndedByDrop(),
      ),
      (
        'the radio closing a requested close changes nothing',
        [request],
        radioClosing,
        ConnectionState.disconnecting,
        null,
        const EndedOnRequest(),
      ),
      (
        'a failed close after the radio began closing stays closing',
        [discovered, request, radioClosing],
        const CloseFailed(),
        ConnectionState.disconnecting,
        null,
        const EndedByDrop(),
      ),
      (
        'a connected report while closing changes nothing',
        [request],
        const RadioReported(LinkReport.connected),
        ConnectionState.disconnecting,
        null,
        const EndedOnRequest(),
      ),
      (
        'a radio close repeated changes nothing',
        [radioClosing],
        radioClosing,
        ConnectionState.disconnecting,
        null,
        const EndedByDrop(),
      ),
      (
        'reports ending while the radio closes is a drop',
        [radioClosing],
        const ReportsEnded(),
        ConnectionState.disconnected,
        LinkDuty.releaseAndAnnounce,
        const EndedByDrop(),
      ),
      (
        'a closing report on a linked link closes it',
        [],
        radioClosing,
        ConnectionState.disconnecting,
        null,
        const EndedByDrop(),
      ),
    ];

    for (final (name, before, input, state, duty, endInSight) in rows) {
      test(name, () {
        // arrange
        final link = after(before);

        // act
        final step = link.on(input);

        // assert
        expect(step.link.state, state);
        expect(step.duty, duty);
        expect(step.link.endInSight, endInSight);
      });
    }
  });

  group('an ended link', () {
    test('ignores every input', () {
      // arrange
      const every = <LinkInput>[
        discovered,
        request,
        radioClosing,
        radioGone,
        ReportsEnded(),
        CloseConfirmed(),
        CloseFailed(),
        RadioReported(LinkReport.connected),
        RadioOutageBegan(RadioOutage.off),
      ];
      final ended = [
        after([radioGone]),
        after([const RadioOutageBegan(RadioOutage.off)]),
      ];

      for (final link in ended) {
        for (final input in every) {
          // act
          final step = link.on(input);

          // assert
          expect(step.link.state, link.state);
          expect(step.link.end, link.end);
          expect(step.duty, isNull);
        }
      }
    });
  });

  group('endInSight', () {
    test('names where a closing link is heading', () {
      // arrange
      final links = {
        'up': after([]),
        'requested': after([request]),
        'radio closing': after([radioClosing]),
        'radio closing, then requested': after([radioClosing, request]),
        'dropped': after([radioGone]),
      };

      // act
      final inSight = links.map(
        (name, link) => MapEntry(name, link.endInSight),
      );

      // assert
      expect(inSight, {
        'up': null,
        'requested': const EndedOnRequest(),
        'radio closing': const EndedByDrop(),
        'radio closing, then requested': const EndedOnRequest(),
        'dropped': const EndedByDrop(),
      });
    });
  });

  group('identity', () {
    test('a link keeps its id and device through every step', () {
      // arrange
      const inputs = [discovered, request, CloseConfirmed()];

      // act
      final link = after(inputs);

      // assert
      expect((link.id, link.device), (id, device));
    });
  });

  group('the flags of each state', () {
    // (state, inputs that reach it, isUp, isClosing, hasEnded)
    final rows = <(ConnectionState, List<LinkInput>, bool, bool, bool)>[
      (ConnectionState.linked, [], true, false, false),
      (ConnectionState.ready, [discovered], true, false, false),
      (ConnectionState.disconnecting, [request], false, true, false),
      (ConnectionState.disconnected, [radioGone], false, false, true),
      (
        ConnectionState.invalidated,
        [const RadioOutageBegan(RadioOutage.unauthorized)],
        false,
        false,
        true,
      ),
    ];

    for (final (state, inputs, isUp, isClosing, hasEnded) in rows) {
      test('a link that is ${state.name}', () {
        // arrange
        final reached = inputs;

        // act
        final link = after(reached);

        // assert
        expect(link.state, state);
        expect(link.isUp, isUp);
        expect(link.isClosing, isClosing);
        expect(link.hasEnded, hasEnded);
      });
    }
  });
}
