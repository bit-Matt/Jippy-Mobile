import 'package:flutter_test/flutter_test.dart';
import 'package:jippy_mobile/utils/polyline_1e6.dart';

void main() {
  test('decodes polyline6 into valid Iloilo bounds', () {
    // From `secrets/current_api.json` (route "Bo. Obrero", goingTo).
    const encoded =
        'os`lSmfdyhFda@p[tMhK~XxTzKvItEbDdEfDtJtH~J|HzBjBpH~FtKvIrRxNzE|DvHdGdL~Id@`@zErDjEhDjP|LtQpMsLxOuUb[kJ~IeFjCiE~A{Dt@{Jh@cCBuF@gGIyDFwBzFeDtEmBhA{Dz@kGbAcEp@aThA}BfBy@hB]dDWv]i@zC_BnBsMhDoTtGkLzDsG~B}DnBwK`ImBjDy@dDc@~E]dG}B`J]lAyBfIiEdKuCjD{FdI}AxBo@bAk`@zh@uEjGaLjOwAnBsJbLoEbI}C~H_BvFsC|K{A|H_B~IcAdGoBvPq@~MQlJItHOv_@]jcAExg@AjKQj\\OlWGrb@AdCGp[A`BW|Dg@dDy@|C}BhGwMdZ{ArDM`CExCTfC~@nDpAjEpEtOo@rClRfz@Jx@PvDdAlJd@lCxCbUYl@Kp@?t@Pr@\\l@h@`@p@Tr@Ft@In@Wl@k@`Bg@dBWtAKlCYzb@S~FCxV@jE@jl@VtKPzHx@xw@H~@?`A?|F@vCAvEAtd@NlX?jA?hC{@`EsCjD{BpAcAd@_@xn@_e@pByA`f@u]zCyBpA{@tDoBrf@oVpCqAjAq@hBdAlLzGlwApw@|AX`BAnFg@z@|f@UnGYY_@Sc@Ic@Ac@HUHQJ_@b@Ob@Eh@Bf@Nd@X^f@Xl@Jn@Cj@Sl@lC^bCPhCf@vP';

    final res = tryDecodePolyline6(encoded);
    expect(res.error, isNull);
    final pts = res.points!;

    // Road-following shapes are typically large-ish (definitely > waypoints).
    expect(pts.length, greaterThanOrEqualTo(150));

    double minLat = 90, maxLat = -90, minLon = 180, maxLon = -180;
    for (final p in pts) {
      minLat = p.latitude < minLat ? p.latitude : minLat;
      maxLat = p.latitude > maxLat ? p.latitude : maxLat;
      minLon = p.longitude < minLon ? p.longitude : minLon;
      maxLon = p.longitude > maxLon ? p.longitude : maxLon;
    }

    // Iloilo City envelope sanity-check (wide bounds to avoid flakiness).
    expect(minLat, greaterThan(10.5));
    expect(maxLat, lessThan(11.0));
    expect(minLon, greaterThan(122.4));
    expect(maxLon, lessThan(122.7));
  });
}

