/* Bad Decisions site: vanilla JS, no dependencies.
   Typing effect adapted from matesuu/Website; the lines are the pet's own
   fallback lines from DesktopApp/ChaosTamagotchi/PetEngine.swift. */
(function () {
    'use strict';

    var reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

    // Real fallback lines from PetEngine.swift (the app uses an LLM when a key is set).
    var LINES = [
        "I can see you. You're not looking at me.",
        'Feed me or I start touching your things.',
        'Day 1 of being ignored. I am fine. (I am not fine.)',
        'Bold of you to have other priorities.'
    ];
    function pick(list) { return list[Math.floor(Math.random() * list.length)]; }

    /* ── Bubble helper ─────────────────────────────────────── */
    function makeSpeaker(bubble) {
        var timer = 0;
        return function say(text, seconds) {
            clearTimeout(timer);
            bubble.textContent = text;
            bubble.classList.add('show');
            timer = setTimeout(function () { bubble.classList.remove('show'); }, (seconds || 7) * 1000);
        };
    }

    /* ── Hero typing (cycles the pet's lines) ──────────────── */
    var typingEl = document.querySelector('[data-typing]');
    if (typingEl) {
        if (reduceMotion) {
            typingEl.textContent = LINES[0];
        } else {
            var lineIdx = 0, charIdx = 0;
            var typingMs = 55, pauseMs = 1800, deleteMs = 22;
            var typeForward = function () {
                charIdx += 1;
                typingEl.textContent = LINES[lineIdx].slice(0, charIdx);
                if (charIdx < LINES[lineIdx].length) setTimeout(typeForward, typingMs);
                else setTimeout(deleteBackward, pauseMs);
            };
            var deleteBackward = function () {
                charIdx -= 1;
                typingEl.textContent = LINES[lineIdx].slice(0, charIdx);
                if (charIdx > 0) {
                    setTimeout(deleteBackward, deleteMs);
                } else {
                    lineIdx = (lineIdx + 1) % LINES.length;
                    setTimeout(typeForward, 350);
                }
            };
            typeForward();
        }
    }

    /* ── Hero pet: cycle moods, poke to talk ──────────────── */
    var heroPet = document.getElementById('hero-pet');
    var heroBubble = document.getElementById('hero-bubble');
    var heroImg = document.getElementById('hero-pet-img');
    var heroMood = document.getElementById('hero-mood');
    var MOODS = [
        { src: 'assets/mona-content.gif', name: 'content' },
        { src: 'assets/mona-restless.gif', name: 'restless' },
        { src: 'assets/mona-anxious.gif', name: 'anxious' },
        { src: 'assets/mona-feral.gif', name: 'feral' },
        { src: 'assets/mona-crimes.gif', name: 'committing crimes' },
        { src: 'assets/mona-sad.gif', name: 'sad' },
        { src: 'assets/mona-happy.gif', name: 'happy' }
    ];
    var moodIdx = 0;
    var talking = false;
    var pokeGen = 0;
    function showMood(entry) {
        if (!heroImg) return;
        heroImg.src = entry.src;
        heroImg.alt = 'Mona, a pixel-art cat, ' + entry.name;
        if (heroMood) heroMood.textContent = entry.name;
    }
    if (heroPet && heroBubble && heroImg) {
        var heroSay = makeSpeaker(heroBubble);
        if (!reduceMotion) {
            setInterval(function () {
                if (talking) return;
                moodIdx = (moodIdx + 1) % MOODS.length;
                showMood(MOODS[moodIdx]);
            }, 3800);
        }
        var poke = function () {
            heroSay(pick(LINES), 4);
            talking = true;
            pokeGen += 1;
            var gen = pokeGen;
            showMood({ src: 'assets/mona-talk.gif', name: 'talking' });
            setTimeout(function () {
                if (gen !== pokeGen) return;
                talking = false;
                showMood(MOODS[moodIdx]);
            }, 4000);
        };
        heroPet.addEventListener('click', poke);
        heroPet.addEventListener('keydown', function (e) {
            if (e.key !== 'Enter' && e.key !== ' ') return;
            e.preventDefault();
            poke();
        });
    }

})();
