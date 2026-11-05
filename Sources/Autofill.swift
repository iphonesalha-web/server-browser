import Foundation

/// سكربت يعبّئ اسم المستخدم وكلمة المرور في صفحة الدخول.
/// لا يضغط زر الدخول ولا يلمس خانة التحقق؛ هذه تبقى للمستخدم.
enum Autofill {
    static func script(username: String, password: String) -> String {
        guard !(username.isEmpty && password.isEmpty),
              let data = try? JSONSerialization.data(withJSONObject: [username, password]),
              let json = String(data: data, encoding: .utf8) else { return "" }

        return """
        (function(){
          var C = \(json);
          var U = C[0], P = C[1];
          function vis(e){ return !!(e.offsetWidth || e.offsetHeight || e.getClientRects().length); }
          function setVal(e, v){
            var d = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value');
            d.set.call(e, v);
            e.dispatchEvent(new Event('input', {bubbles:true}));
            e.dispatchEvent(new Event('change', {bubbles:true}));
          }
          var done = false;
          function fill(){
            if (done) return;
            var pws = Array.prototype.filter.call(document.querySelectorAll('input[type=password]'), vis);
            if (!pws.length) return;
            var pw = pws[0];
            var all = Array.prototype.filter.call(document.querySelectorAll('input'), function(e){
              var t = (e.getAttribute('type') || 'text').toLowerCase();
              return vis(e) && (t === 'text' || t === 'email' || t === 'tel');
            });
            var user = null;
            for (var i = 0; i < all.length; i++) {
              if (all[i].compareDocumentPosition(pw) & Node.DOCUMENT_POSITION_FOLLOWING) { user = all[i]; }
            }
            if (U && user && !user.value) { setVal(user, U); }
            if (P && !pw.value) { setVal(pw, P); }
            done = true;
          }
          fill();
          var n = 0;
          var t = setInterval(function(){ fill(); n++; if (done || n > 40) { clearInterval(t); } }, 500);
        })();
        """
    }
}
