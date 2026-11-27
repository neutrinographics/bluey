import 'package:bluey/src/features/connection/domain/link.dart';
import 'package:bluey/src/features/connection/domain/link_end.dart';
import 'package:bluey/src/features/connection/domain/link_event.dart';
import 'package:bluey/src/features/connection/domain/link_id.dart';
import 'package:bluey/src/features/connection/domain/link_input.dart';
import 'package:bluey/src/features/connection/domain/link_phase.dart';
import 'package:bluey/src/shared/domain/device_address.dart';
import 'package:flutter_test/flutter_test.dart';

const id = LinkId('L1');
const device = DeviceAddress('AA:BB:CC:DD:EE:01');
final opened = DateTime.utc(2026, 11, 26, 9);
final at = DateTime.utc(2026, 11, 26, 10);

Link opening() => Link.begin(device: device, at: opened).link;

Link after(List<LinkInput> inputs) => inputs.fold(
  Link.open(id: id, device: device, at: opened).link,
  (link, input) => link.on(input, at: opened).link,
);

const discovered = ServicesDiscovered();
const request = DisconnectRequested();
const radioClosing = RadioReported(LinkReport.disconnecting);
const radioGone = RadioReported(LinkReport.disconnected);

const linked = Linked();
const ready = Ready();
const onRequest = Ended(EndedOnRequest());
const dropped = Ended(EndedByDrop());

Closing closing(UpPhase returnTo, ClosingBy by) =>
    Closing(returnTo: returnTo, by: by);

typedef Row =
    (
      String name,
      List<LinkInput> before,
      LinkInput input,
      LinkPhase phase,
      LinkEnd? end,
      LinkDuty? duty,
      LinkPhase? entered,
      LinkEnd? endInSight,
    );

void checkEach(List<Row> rows) {
  for (final (name, before, input, phase, end, duty, entered, endInSight)
      in rows) {
    test(name, () {
      // arrange
      final link = after(before);

      // act
      final step = link.on(input, at: at);

      // assert
      expect(step.link.phase, phase);
      expect(step.link.end, end);
      expect(step.duty, duty);
      expect(step.entered, entered);
      expect(step.link.endInSight, endInSight);
      expect(step.events, [
        if (end != null) LinkEnded(device: device, at: at, end: end),
      ]);
    });
  }
}

void main() {
  group('opening', () {
    test('a link opens linked and raises that it opened', () {
      // act
      final step = Link.open(id: id, device: device, at: at);

      // assert
      expect(step.link.phase, linked);
      expect((step.link.id, step.link.device), (id, device));
      expect(step.entered, linked);
      expect(step.duty, isNull);
      expect(step.events, [LinkOpened(device: device, at: at)]);
    });

    test('a step\'s events cannot be changed by whoever reads them', () {
      // arrange
      final step = Link.open(id: id, device: device, at: at);

      // act
      void addAnEvent() => step.events.add(LinkOpened(device: device, at: at));

      // assert
      expect(addAnEvent, throwsUnsupportedError);
    });
  });

  group('beginning', () {
    test('a link begins opening, with no id, and raises that its open '
        'began', () {
      // act
      final step = Link.begin(device: device, at: at);

      // assert
      expect(step.link.phase, const Opening());
      expect((step.link.id, step.link.device), (null, device));
      expect(step.link.endInSight, isNull);
      expect(step.entered, const Opening());
      expect(step.duty, isNull);
      expect(step.events, [LinkOpenBegan(device: device, at: at)]);
    });

    test('an open that succeeds links it under the id and raises that it '
        'opened', () {
      // act
      final step = opening().on(const OpenSucceeded(id), at: at);

      // assert
      expect(step.link.phase, linked);
      expect((step.link.id, step.link.device), (id, device));
      expect(step.entered, linked);
      expect(step.duty, const FollowTheLink(id));
      expect(step.events, [LinkOpened(device: device, at: at)]);
    });

    test('an open that fails leaves a link that never opened, and raises '
        'nothing', () {
      // act
      final step = opening().on(const OpenFailed(), at: at);

      // assert
      expect(step.link.phase, const NeverOpened());
      expect(
        (step.link.id, step.link.end, step.link.endInSight),
        (null, null, null),
      );
      expect(
        (step.link.isUp, step.link.isClosing, step.link.hasEnded),
        (false, false, false),
      );
      expect(step.entered, const NeverOpened());
      expect(step.duty, const ForgetTheLink());
      expect(step.events, isEmpty);
    });

    const others = <LinkInput>[
      discovered,
      request,
      RadioReported(LinkReport.connecting),
      RadioReported(LinkReport.connected),
      radioClosing,
      radioGone,
      ReportsEnded(),
      CloseConfirmed(),
      CloseFailed(),
      RadioOutageBegan(RadioOutage.off),
    ];

    test('an opening link waits for its open\'s answer, whatever else '
        'happens', () {
      for (final input in others) {
        // arrange
        final link = opening();

        // act
        final step = link.on(input, at: at);

        // assert
        expect(step.link, same(link), reason: '$input');
        expect(step.duty, isNull, reason: '$input');
        expect(step.entered, isNull, reason: '$input');
        expect(step.events, isEmpty, reason: '$input');
      }
    });

    test('a link that never opened answers everything with itself', () {
      // arrange
      final never = opening().on(const OpenFailed(), at: at).link;

      for (final input in [
        ...others,
        const OpenSucceeded(id),
        const OpenFailed(),
      ]) {
        // act
        final step = never.on(input, at: at);

        // assert
        expect(step.link, same(never), reason: '$input');
        expect(step.duty, isNull, reason: '$input');
        expect(step.entered, isNull, reason: '$input');
        expect(step.events, isEmpty, reason: '$input');
      }
    });

    test('a link past its open ignores a late answer to it', () {
      // arrange
      final past = [
        after([]),
        after([discovered]),
        after([request]),
        after([radioGone]),
      ];

      for (final link in past) {
        for (final input in const [OpenSucceeded(LinkId('L2')), OpenFailed()]) {
          // act
          final step = link.on(input, at: at);

          // assert
          expect(step.link, same(link), reason: '${link.phase} $input');
          expect(step.link.id, id);
          expect(step.duty, isNull);
          expect(step.entered, isNull);
          expect(step.events, isEmpty);
        }
      }
    });
  });

  group('the lifecycle table', () {
    checkEach([
      (
        'discovery makes a linked link ready',
        [],
        discovered,
        ready,
        null,
        null,
        ready,
        null,
      ),
      (
        'a repeated connected report never takes ready back to linked',
        [discovered],
        const RadioReported(LinkReport.connected),
        ready,
        null,
        null,
        null,
        null,
      ),
      (
        'a connecting report changes nothing',
        [],
        const RadioReported(LinkReport.connecting),
        linked,
        null,
        null,
        null,
        null,
      ),
      (
        'the radio closing the link',
        [discovered],
        radioClosing,
        closing(ready, ClosingBy.radio),
        null,
        null,
        closing(ready, ClosingBy.radio),
        const EndedByDrop(),
      ),
      (
        'a request asks for the close',
        [discovered],
        request,
        closing(ready, ClosingBy.request),
        null,
        const CloseTheLink(id),
        closing(ready, ClosingBy.request),
        const EndedOnRequest(),
      ),
      (
        'a second request joins the close in flight',
        [request],
        request,
        closing(linked, ClosingBy.request),
        null,
        null,
        null,
        const EndedOnRequest(),
      ),
      (
        'a request while the radio is closing asks for the close, and has '
            'not entered closing again',
        [radioClosing],
        request,
        closing(linked, ClosingBy.both),
        null,
        const CloseTheLink(id),
        null,
        const EndedOnRequest(),
      ),
      (
        'a confirmed close ends on request',
        [request],
        const CloseConfirmed(),
        onRequest,
        const EndedOnRequest(),
        const ReleaseTheLink(EndedOnRequest()),
        onRequest,
        const EndedOnRequest(),
      ),
      (
        'a disconnected report ends a requested close on request',
        [request],
        radioGone,
        onRequest,
        const EndedOnRequest(),
        const ReleaseTheLink(EndedOnRequest()),
        onRequest,
        const EndedOnRequest(),
      ),
      (
        'reports ending ends a requested close on request',
        [request],
        const ReportsEnded(),
        onRequest,
        const EndedOnRequest(),
        const ReleaseTheLink(EndedOnRequest()),
        onRequest,
        const EndedOnRequest(),
      ),
      (
        'the radio finishing its own close is a drop',
        [radioClosing],
        radioGone,
        dropped,
        const EndedByDrop(),
        const ReleaseTheLink(EndedByDrop()),
        dropped,
        const EndedByDrop(),
      ),
      (
        'a failed close returns to ready',
        [discovered, request],
        const CloseFailed(),
        ready,
        null,
        null,
        ready,
        null,
      ),
      (
        'a failed close returns to linked',
        [request],
        const CloseFailed(),
        linked,
        null,
        null,
        linked,
        null,
      ),
      (
        'a drop ends a linked link',
        [],
        radioGone,
        dropped,
        const EndedByDrop(),
        const ReleaseTheLink(EndedByDrop()),
        dropped,
        const EndedByDrop(),
      ),
      (
        'reports ending is a drop',
        [discovered],
        const ReportsEnded(),
        dropped,
        const EndedByDrop(),
        const ReleaseTheLink(EndedByDrop()),
        dropped,
        const EndedByDrop(),
      ),
      (
        'an outage invalidates an up link',
        [discovered],
        const RadioOutageBegan(RadioOutage.off),
        const Ended(EndedByRadioOutage(RadioOutage.off)),
        const EndedByRadioOutage(RadioOutage.off),
        const ReleaseTheLink(EndedByRadioOutage(RadioOutage.off)),
        const Ended(EndedByRadioOutage(RadioOutage.off)),
        const EndedByRadioOutage(RadioOutage.off),
      ),
      (
        'an outage invalidates a closing link',
        [request],
        const RadioOutageBegan(RadioOutage.unknown),
        const Ended(EndedByRadioOutage(RadioOutage.unknown)),
        const EndedByRadioOutage(RadioOutage.unknown),
        const ReleaseTheLink(EndedByRadioOutage(RadioOutage.unknown)),
        const Ended(EndedByRadioOutage(RadioOutage.unknown)),
        const EndedByRadioOutage(RadioOutage.unknown),
      ),
      (
        'a stray close answer changes nothing',
        [discovered],
        const CloseConfirmed(),
        ready,
        null,
        null,
        null,
        null,
      ),
      (
        'discovery while closing changes nothing',
        [request],
        discovered,
        closing(linked, ClosingBy.request),
        null,
        null,
        null,
        const EndedOnRequest(),
      ),
    ]);
  });

  group('the cases the table leaves to the builder', () {
    checkEach([
      (
        'a stray close failure on an up link changes nothing',
        [discovered],
        const CloseFailed(),
        ready,
        null,
        null,
        null,
        null,
      ),
      (
        'a close the radio ends before it is asked is not answered',
        [radioClosing],
        const CloseConfirmed(),
        closing(linked, ClosingBy.radio),
        null,
        null,
        null,
        const EndedByDrop(),
      ),
      (
        'a close failure the radio was not asked for changes nothing',
        [radioClosing],
        const CloseFailed(),
        closing(linked, ClosingBy.radio),
        null,
        null,
        null,
        const EndedByDrop(),
      ),
      (
        'a failed close while the radio is closing stays closing, '
            'heading for a drop',
        [discovered, radioClosing, request],
        const CloseFailed(),
        closing(ready, ClosingBy.radio),
        null,
        null,
        null,
        const EndedByDrop(),
      ),
      (
        'the radio closing a requested close changes nothing',
        [request],
        radioClosing,
        closing(linked, ClosingBy.request),
        null,
        null,
        null,
        const EndedOnRequest(),
      ),
      (
        'a closing report during a requested close is its echo, so a failed '
            'close returns to ready',
        [discovered, request, radioClosing],
        const CloseFailed(),
        ready,
        null,
        null,
        ready,
        null,
      ),
      (
        'a request leaves a link a failed close left closing',
        [discovered, radioClosing, request, const CloseFailed()],
        request,
        closing(ready, ClosingBy.both),
        null,
        const CloseTheLink(id),
        null,
        const EndedOnRequest(),
      ),
      (
        'a connected report while closing changes nothing',
        [request],
        const RadioReported(LinkReport.connected),
        closing(linked, ClosingBy.request),
        null,
        null,
        null,
        const EndedOnRequest(),
      ),
      (
        'a radio close repeated changes nothing',
        [radioClosing],
        radioClosing,
        closing(linked, ClosingBy.radio),
        null,
        null,
        null,
        const EndedByDrop(),
      ),
      (
        'reports ending while the radio closes is a drop',
        [radioClosing],
        const ReportsEnded(),
        dropped,
        const EndedByDrop(),
        const ReleaseTheLink(EndedByDrop()),
        dropped,
        const EndedByDrop(),
      ),
      (
        'a closing report on a linked link closes it',
        [],
        radioClosing,
        closing(linked, ClosingBy.radio),
        null,
        null,
        closing(linked, ClosingBy.radio),
        const EndedByDrop(),
      ),
      (
        'a request and the radio both closing end on request',
        [radioClosing, request],
        radioGone,
        onRequest,
        const EndedOnRequest(),
        const ReleaseTheLink(EndedOnRequest()),
        onRequest,
        const EndedOnRequest(),
      ),
      (
        'a confirmed close while the radio also closes ends on request',
        [radioClosing, request],
        const CloseConfirmed(),
        onRequest,
        const EndedOnRequest(),
        const ReleaseTheLink(EndedOnRequest()),
        onRequest,
        const EndedOnRequest(),
      ),
    ]);
  });

  group('an ended link', () {
    test('answers every input with the same link, no duty and no phase '
        'entered', () {
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
        after([request, const CloseConfirmed()]),
        after([radioGone]),
        after([const RadioOutageBegan(RadioOutage.off)]),
      ];

      for (final link in ended) {
        for (final input in every) {
          // act
          final step = link.on(input, at: at);

          // assert
          expect(step.link, same(link));
          expect(step.duty, isNull);
          expect(step.entered, isNull);
          expect(step.events, isEmpty);
        }
      }
    });
  });

  group('duties', () {
    test('are equal by value', () {
      // assert
      expect(const CloseTheLink(id), const CloseTheLink(id));
      expect(const CloseTheLink(id).hashCode, const CloseTheLink(id).hashCode);
      expect(const CloseTheLink(id), isNot(const CloseTheLink(LinkId('L2'))));
      expect(const FollowTheLink(id), const FollowTheLink(id));
      expect(
        const FollowTheLink(id).hashCode,
        const FollowTheLink(id).hashCode,
      );
      expect(const FollowTheLink(id), isNot(const FollowTheLink(LinkId('L2'))));
      expect(const ForgetTheLink(), const ForgetTheLink());
      expect(const ForgetTheLink().hashCode, const ForgetTheLink().hashCode);
      expect(const ForgetTheLink(), isNot(const FollowTheLink(id)));
      expect(
        const ReleaseTheLink(EndedByDrop()).hashCode,
        const ReleaseTheLink(EndedByDrop()).hashCode,
      );
      expect(
        const ReleaseTheLink(EndedByDrop()),
        isNot(const ReleaseTheLink(EndedOnRequest())),
      );
      expect(
        const CloseTheLink(id),
        isNot(const ReleaseTheLink(EndedByDrop())),
      );
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

  group('the flags of each phase', () {
    // (name, inputs that reach it, isUp, isClosing, hasEnded)
    final rows = <(String, List<LinkInput>, bool, bool, bool)>[
      ('linked', [], true, false, false),
      ('ready', [discovered], true, false, false),
      ('closing', [request], false, true, false),
      ('ended by a drop', [radioGone], false, false, true),
      (
        'ended by an outage',
        [const RadioOutageBegan(RadioOutage.unauthorized)],
        false,
        false,
        true,
      ),
    ];

    test('a link that is opening', () {
      // act
      final link = opening();

      // assert
      expect(link.isUp, isFalse);
      expect(link.isClosing, isFalse);
      expect(link.hasEnded, isFalse);
    });

    for (final (name, inputs, isUp, isClosing, hasEnded) in rows) {
      test('a link that is $name', () {
        // act
        final link = after(inputs);

        // assert
        expect(link.isUp, isUp);
        expect(link.isClosing, isClosing);
        expect(link.hasEnded, hasEnded);
      });
    }
  });
}
