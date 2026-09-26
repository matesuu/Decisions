/* Pickle site: vanilla JS, no dependencies.
   Scroll reveals, the scripted desktop demo, scenery parallax, agent flow, control tabs,
   terminal typing, and an idle-page poop easter egg. */
(function () {
    'use strict';

    var reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    var $ = function (s, r) { return (r || document).querySelector(s); };
    var $$ = function (s, r) { return Array.prototype.slice.call((r || document).querySelectorAll(s)); };
    var rand = function (a, b) { return a + Math.random() * (b - a); };
    var pick = function (l) { return l[Math.floor(Math.random() * l.length)]; };

    var LINES = [
        'hi :3', 'pet me?', 'boop.', 'I have notes.', 'scoot.',
        'hellooo?', 'feed me?', 'nom. fine. forgiven. for now.'
    ];

    /* ── Reveal on scroll ─────────────────────────────────── */
    var revealObs = new IntersectionObserver(function (entries) {
        entries.forEach(function (e) {
            if (e.isIntersecting) { e.target.classList.add('visible'); revealObs.unobserve(e.target); }
        });
    }, { threshold: 0.12, rootMargin: '0px 0px -40px 0px' });
    $$('.reveal').forEach(function (el) { revealObs.observe(el); });

    /* ── Nav, edge CTA, scenery parallax ──────────────────── */
    var nav = $('.nav'), edge = $('#edge-cta'), ridges = $$('.ridge'), sun = $('.sun');
    var onScrollTop = function () {
        var y = window.scrollY;
        nav.classList.toggle('scrolled', y > 8);
        if (edge) edge.classList.toggle('show', y > window.innerHeight * 0.9);
        if (!reduceMotion && y < 900) {
            ridges.forEach(function (r, i) { r.style.transform = 'translateY(' + (y * (0.08 + i * 0.07)) + 'px)'; });
            if (sun) sun.style.translate = '0 ' + (y * 0.25) + 'px';
        }
    };
    window.addEventListener('scroll', onScrollTop, { passive: true });
    onScrollTop();

    /* 3D tilt on the mischief tiles */
    if (!reduceMotion) {
        $$('.art').forEach(function (art) {
            art.addEventListener('pointermove', function (e) {
                var r = art.getBoundingClientRect();
                var dx = (e.clientX - r.left) / r.width - 0.5, dy = (e.clientY - r.top) / r.height - 0.5;
                art.style.transform = 'perspective(600px) rotateY(' + (dx * 12) + 'deg) rotateX(' + (-dy * 12) + 'deg) translateY(-4px)';
            });
            art.addEventListener('pointerleave', function () { art.style.transform = ''; });
        });
    }

    /* ── Headline word swap ───────────────────────────────── */
    var swapEl = $('[data-swap]');
    var WORDS = ['Desktop Menace', 'Screen Goblin', 'Chaos Roommate', 'Emotional Burden'];
    if (swapEl && !reduceMotion) {
        var wi = 0;
        setInterval(function () {
            swapEl.classList.add('out');
            setTimeout(function () {
                wi = (wi + 1) % WORDS.length;
                swapEl.textContent = WORDS[wi];
                swapEl.classList.remove('out');
                swapEl.classList.add('in');
                void swapEl.offsetWidth;  // restart transition
                swapEl.classList.remove('in');
            }, 450);
        }, 3000);
    }

    /* ── Hero demo: a scripted escalation, every crime announced first ── */
    var mac = $('#mac');
    if (mac) {
        var pet = $('#demo-pet'), petImg = $('#demo-pet img'), cursor = $('#demo-cursor'), poops = $('#demo-poops'), sayEl = $('#demo-say');
        var healthEl = $('#demo-health'), moodEl = $('#demo-mood'), chip = $('#demo-chip'), meter = $('#demo-meter');
        var MOODS = [[75, 'content'], [50, 'restless'], [25, 'anxious'], [0.01, 'feral'], [-1, 'crimes']];
        var DRAIN = 15;  // seconds from 100% to crimes
        var timers = [], roamTimer = 0, tickTimer = 0, sayTimer = 0, start = 0, demoVisible = true;

        var later = function (s, fn) { timers.push(setTimeout(fn, s * 1000)); };
        var say = function (text, secs) {
            clearTimeout(sayTimer);
            sayEl.textContent = text;
            sayEl.classList.remove('show'); void sayEl.offsetWidth; sayEl.classList.add('show');
            sayTimer = setTimeout(function () { sayEl.classList.remove('show'); }, (secs || 1.8) * 1000);
        };
        var setCursor = function (x, y) {
            cursor.style.setProperty('--cx', x + 'px');
            cursor.style.setProperty('--cy', y + 'px');
        };
        var roam = function () {
            var mood = mac.getAttribute('data-mood');
            var fast = mood === 'feral' || mood === 'crimes';
            var x = rand(0, 640), y = rand(160, 340);
            var cur = parseFloat(pet.style.getPropertyValue('--px')) || 300;
            pet.style.setProperty('--face', x > cur ? -1 : 1);
            pet.style.setProperty('--pet-speed', fast ? '0.9s' : mood === 'content' ? '2.6s' : '1.6s');
            pet.style.setProperty('--px', x + '%');
            pet.style.setProperty('--py', y + '%');
            roamTimer = setTimeout(roam, fast ? 900 : mood === 'content' ? 2600 : 1600);
        };
        var dropPoop = function (n) {
            for (var i = 0; i < n; i++) {
                var s = document.createElement('span');
                s.textContent = '💩';
                s.style.left = rand(8, 88) + '%';
                s.style.top = rand(55, 88) + '%';
                s.style.animationDelay = (i * 0.15) + 's';
                poops.appendChild(s);
            }
        };
        var tick = function () {
            var t = (performance.now() - start) / 1000;
            var h = Math.max(0, 100 - (t / DRAIN) * 100);
            var mood = 'crimes';
            for (var i = 0; i < MOODS.length; i++) { if (h > MOODS[i][0]) { mood = MOODS[i][1]; break; } }
            healthEl.textContent = Math.round(h);
            meter.style.transform = 'scaleX(' + (h / 100) + ')';
            if (mac.getAttribute('data-mood') !== mood) {
                mac.setAttribute('data-mood', mood);
                petImg.src = 'assets/mona-' + mood + '.gif';
                moodEl.textContent = mood;
                chip.textContent = mood === 'crimes' ? 'committing crimes' : mood;
                chip.classList.toggle('hot', mood === 'feral' || mood === 'crimes');
            }
        };
        var hijack = function () {
            mac.classList.add('hijack');
            var w = mac.clientWidth, h = mac.clientHeight, n = 0;
            var jerk = setInterval(function () {
                setCursor(rand(20, w - 30), rand(40, h - 30));
                if (++n > 9) { clearInterval(jerk); mac.classList.remove('hijack'); }
            }, 130);
            timers.push(jerk);
        };
        var reset = function () {
            timers.forEach(function (id) { clearTimeout(id); clearInterval(id); });
            timers = [];
            clearInterval(tickTimer);
            mac.className = 'mac';
            poops.innerHTML = '';
            mac.setAttribute('data-mood', '');
        };
        var run = function () {
            reset();
            start = performance.now();
            tick();
            tickTimer = setInterval(tick, 250);
            var w = mac.clientWidth, h = mac.clientHeight;
            setCursor(w * 0.62, h * 0.5);
            later(0.8, function () { say('hi :3'); });
            later(2.2, function () { dropPoop(1); });
            later(3.4, function () { say('I have notes.'); });
            later(4.6, function () { mac.classList.add('noted'); });
            later(6.6, function () { say('scoot.'); });
            later(7.8, function () { mac.classList.add('nudged'); });
            later(9.0, function () { say('gimme the mouse.'); });
            later(9.8, hijack);
            later(11.4, function () { say('ultimatum. pick one.', 2.4); mac.classList.add('ult'); });
            later(13.0, function () { mac.classList.add('picked'); });
            later(13.6, function () { mac.classList.remove('ult'); say('fine. DJ time.'); });
            later(14.4, function () { mac.classList.add('spotify'); dropPoop(2); });
            later(15.4, function () { say("that's it. texting your friend.", 2.4); });
            later(16.4, function () { mac.classList.add('texting'); });
            later(17.8, function () { mac.classList.add('sent'); });
            later(20, function () { feed(); });
        };
        var feed = function () {
            reset();
            mac.setAttribute('data-mood', 'content');
            chip.textContent = 'fed ✓';
            chip.classList.remove('hot');
            healthEl.textContent = '100';
            moodEl.textContent = 'content';
            meter.style.transform = 'scaleX(1)';
            petImg.src = 'assets/mona-happy.gif';
            say('nom. forgiven.');
            timers.push(setTimeout(function () { if (demoVisible) run(); }, 1600));
        };
        $('#demo-feed').addEventListener('click', feed);

        if (reduceMotion) {
            mac.setAttribute('data-mood', 'feral');
            mac.classList.add('noted', 'spotify');
            dropPoop(3);
        } else {
            // Only animate while on screen.
            new IntersectionObserver(function (entries) {
                demoVisible = entries[0].isIntersecting;
                if (demoVisible) { if (!start || !mac.getAttribute('data-mood')) run(); roam(); }
                else { reset(); clearTimeout(roamTimer); start = 0; }
            }, { threshold: 0.2 }).observe(mac);
        }
    }

    /* ── Agent flow + terminal typing ─────────────────────── */
    var flow = $('#flow'), term = $('#term code');
    var TERM = [
        ['<span class="c">$</span> python3 chaos_action.py <span class="g">"Ignored for 5 min. Pooped 23 times."</span>', 0],
        ['<span class="b">→</span> asking the LLM for two options <span class="c">(JSON mode)</span>', 1],
        ['  option_a  <span class="g">"Hostage update"</span>', 1],
        ['  option_b  <span class="g">"Passive-aggressive iMessage"</span>', 1],
        ['<span class="k">●</span> coin flip → <span class="k">option_b</span>', 2],
        ['<span class="b">→</span> Contacts: Mateo Alado → <span class="c">+1 ••• ••• ••42</span>', 3],
        ['<span class="b">→</span> opening Messages… <span class="g">sent ✓</span>', 4],
        ['<span class="c">{"label": "Passive-aggressive iMessage", "outcome": "Opened Messages and texted Mateo Alado"}</span>', 4]
    ];
    if (flow && term) {
        var steps = $$('.step', flow), ran = false;
        var play = function () {
            if (ran) return;
            ran = true;
            flow.classList.add('run');
            var i = 0;
            var next = function () {
                if (i >= TERM.length) {
                    term.insertAdjacentHTML('beforeend', '<span class="caret"></span>');
                    setTimeout(function () { steps.forEach(function (n) { n.classList.remove('active'); }); }, 2000);
                    return;
                }
                steps.forEach(function (n, k) { n.classList.toggle('active', k === TERM[i][1]); });
                term.insertAdjacentHTML('beforeend', TERM[i][0] + '\n');
                i++;
                setTimeout(next, reduceMotion ? 0 : (i === 1 ? 900 : 650));
            };
            next();
        };
        new IntersectionObserver(function (entries) {
            if (entries[0].isIntersecting) play();
        }, { threshold: 0.35 }).observe(flow);
    }

    /* ── Control tabs: auto-advance, click to pick ─────────── */
    var tabs = $$('#tabs .tab'), arts = $$('[data-tab-art]'), tabIdx = 0, tabTimer = 0, TAB_MS = 4500;
    var showTab = function (i) {
        tabIdx = i;
        tabs.forEach(function (t, k) {
            t.classList.remove('on');
            if (k === i) { void t.offsetWidth; t.classList.add('on'); }
        });
        arts.forEach(function (a) { a.classList.toggle('on', +a.getAttribute('data-tab-art') === i); });
        clearTimeout(tabTimer);
        if (!reduceMotion) tabTimer = setTimeout(function () { showTab((tabIdx + 1) % tabs.length); }, TAB_MS);
    };
    if (tabs.length) {
        document.documentElement.style.setProperty('--tab-ms', TAB_MS + 'ms');
        tabs.forEach(function (t, k) { t.addEventListener('click', function () { showTab(k); }); });
        showTab(0);
    }

    /* ── Copy setup commands ──────────────────────────────── */
    var copyBtn = $('#copy'), setupCode = $('#setup-code');
    if (copyBtn && setupCode) {
        copyBtn.addEventListener('click', function () {
            var text = setupCode.innerText.split('\n').filter(function (l) { return l && l.charAt(0) !== '#'; }).join('\n');
            (navigator.clipboard ? navigator.clipboard.writeText(text) : Promise.reject()).then(function () {
                copyBtn.textContent = 'Copied';
                copyBtn.classList.add('done');
                setTimeout(function () { copyBtn.textContent = 'Copy'; copyBtn.classList.remove('done'); }, 1600);
            }).catch(function () { copyBtn.textContent = 'Select & copy'; });
        });
    }

    /* ── Poke the pet ─────────────────────────────────────── */
    var bubble = $('#bubble'), bubbleTimer = 0;
    var pokeSay = function (text, secs) {
        if (!bubble) return;
        clearTimeout(bubbleTimer);
        bubble.textContent = text;
        bubble.classList.add('show');
        bubbleTimer = setTimeout(function () { bubble.classList.remove('show'); }, (secs || 4) * 1000);
    };
    var poke = $('#poke');
    var pokeImg = poke && poke.querySelector('img'), talkTimer = 0;
    if (poke) poke.addEventListener('click', function () {
        pokeSay(pick(LINES));
        pokeImg.src = 'assets/mona-talk.gif';
        clearTimeout(talkTimer);
        talkTimer = setTimeout(function () { pokeImg.src = 'assets/mona-content.gif'; }, 4000);
    });

    /* ── Idle page? Pickle poops on it. Click to clean. ───── */
    var layer = $('#page-poops'), idleTimer = 0, poopTimer = 0, count = 0;
    var dropPagePoop = function () {
        if (count >= 12) return;
        var b = document.createElement('button');
        b.type = 'button';
        b.textContent = '💩';
        b.setAttribute('aria-label', 'Clean up poop');
        b.style.left = rand(4, 92) + 'vw';
        b.style.top = rand(12, 86) + 'vh';
        b.addEventListener('click', function () {
            b.classList.add('gone');
            count--;
            setTimeout(function () { b.remove(); }, 260);
            if (count === 0) pokeSay('You cleaned it all. I’ll make more.');
        });
        layer.appendChild(b);
        count++;
        if (count === 1) pokeSay('You stopped scrolling. So I pooped.', 5);
        poopTimer = setTimeout(dropPagePoop, 3500);
    };
    var active = function () {
        clearTimeout(idleTimer);
        clearTimeout(poopTimer);
        idleTimer = setTimeout(dropPagePoop, 15000);
    };
    if (layer && !reduceMotion) {
        ['pointermove', 'keydown', 'scroll', 'touchstart'].forEach(function (ev) {
            window.addEventListener(ev, active, { passive: true });
        });
        active();
    }
})();
