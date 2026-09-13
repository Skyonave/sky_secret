import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/core/desktop/search_session.dart';

void main() {
  test('selection belongs to the latest nonempty query and active vault session', () {
    var unlocked = true;
    var activities = 0;
    final session = VaultSearchSession(
      isValid: () => unlocked,
      find: (query) => [
        {'id': query, 'title': query},
      ],
      activity: () => activities++,
    );
    expect(session.accepts('first'), isFalse);
    expect(session.search('first').single['id'], 'first');
    expect(session.accepts('first'), isTrue);
    expect(session.search('second').single['id'], 'second');
    expect(session.accepts('first'), isFalse);
    expect(session.accepts('second'), isTrue);
    expect(session.search(' '), isEmpty);
    expect(session.accepts('second'), isFalse);
    session.search('third');
    unlocked = false;
    expect(session.accepts('third'), isFalse);
    expect(session.search('fourth'), isEmpty);
    expect(activities, 3);
  });

  test('closed search remains revoked after vault unlock and enforces query/result limits', () {
    var unlocked = true;
    var lookups = 0;
    final session = VaultSearchSession(
      isValid: () => unlocked,
      find: (_) {
        lookups++;
        return List.generate(60, (index) => {'id': '$index'});
      },
      activity: () {},
    );
    expect(session.search('x' * 257), isEmpty);
    expect(lookups, 0);
    expect(session.search('x').length, 50);
    expect(session.accepts('49'), isTrue);
    expect(session.accepts('50'), isFalse);
    session.close();
    unlocked = false;
    unlocked = true;
    expect(session.accepts('49'), isFalse);
    expect(session.search('x'), isEmpty);
    expect(lookups, 1);
  });
}
