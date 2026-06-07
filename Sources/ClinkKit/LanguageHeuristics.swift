/**
 Per-language heuristic tables for `SuggestionEngine`. `UITextChecker` already
 handles completions, spelling guesses, and misspelling detection in whatever
 language it's pointed at — but three pieces of the suggestion bar are NOT covered
 by the checker and used to be hardcoded English:

   • next-word prediction (the bar before/between words has no partial to complete,
     so we predict the likely next word from a compact bigram map),
   • contraction auto-punctuation (apostrophe-less → real form, "dont" → "don't"),
   • common-word ranking (the checker returns completions alphabetically, so we
     float the everyday word to the top).

 Those are language-specific, so they live here keyed by language code. The engine
 picks the matching set in `setLanguage`; an unknown language (incl. CJK, which
 needs a full input-method engine well beyond `UITextChecker`) gets `.empty` and
 leans entirely on the checker — the bar still completes/corrects, it just has no
 next-word guess or contraction expansion.
 */
import Foundation

/// The language-specific heuristics the suggestion engine layers on top of
/// `UITextChecker`. Resolved by language code (the part of a `UITextChecker`
/// identifier before the region — "fr" from "fr_FR"), so "en_US"/"en_GB" share
/// one set and "pt_PT"/"pt_BR" share another.
struct LanguageHeuristics {
    /// Capitalised openers shown at the start of a sentence.
    let sentenceStarters: [String]
    /// High-frequency words shown when we have no specific follow-on.
    let commonFallback: [String]
    /// word → words that frequently follow it (a compact common-bigram map, not a
    /// full language model — just enough that mid-sentence predictions feel
    /// plausible and the bar always has something useful).
    let bigrams: [String: [String]]
    /// Apostrophe-less → contraction, for auto-punctuation. Conservative per
    /// language: omits forms that are also common standalone words, so we never
    /// rewrite a valid word. Keys lowercased; values carry canonical casing.
    let contractions: [String: String]
    /// Common words used to rank completions by likelihood — membership (not exact
    /// frequency) is enough to float the everyday word to the top.
    let commonWords: Set<String>

    /// No heuristics — used for any language we don't ship tables for. The bar
    /// still works off `UITextChecker`; it just offers no next-word guess,
    /// contraction expansion, or extra ranking.
    static let empty = LanguageHeuristics(
        sentenceStarters: [], commonFallback: [], bigrams: [:],
        contractions: [:], commonWords: [])

    /// Pick the heuristics for a `UITextChecker` language identifier (e.g.
    /// "en_US", "fr_FR", "ru_RU"). Matches on the language code before the region
    /// separator; falls back to `.empty` for anything we don't ship.
    static func forLanguage(_ identifier: String) -> LanguageHeuristics {
        let code = identifier.prefix { $0 != "_" && $0 != "-" }.lowercased()
        return table[String(code)] ?? .empty
    }

    private static let table: [String: LanguageHeuristics] = [
        "en": english, "fr": french, "es": spanish, "de": german,
        "it": italian, "pt": portuguese, "ru": russian,
    ]
}

// MARK: - English

private extension LanguageHeuristics {
    static let english = LanguageHeuristics(
        sentenceStarters: ["I", "I'm", "The"],
        commonFallback: ["the", "to", "and"],
        bigrams: [
            "i": ["am", "have", "think", "don't", "was", "will"],
            "i'm": ["going", "not", "so", "just", "sorry"],
            "the": ["best", "same", "first", "most", "other"],
            "a": ["lot", "few", "little", "good", "great"],
            "to": ["be", "the", "do", "get", "go"],
            "you": ["are", "can", "have", "know", "want"],
            "what": ["is", "are", "do", "time", "happened"],
            "how": ["are", "do", "much", "many", "about"],
            "when": ["are", "you", "is", "the", "will"],
            "where": ["are", "is", "you", "the", "do"],
            "why": ["are", "is", "do", "not", "would"],
            "thanks": ["for", "so", "a"],
            "thank": ["you"],
            "good": ["morning", "luck", "idea", "to"],
            "is": ["the", "a", "that", "it", "this"],
            "are": ["you", "the", "we", "they", "going"],
            "have": ["a", "to", "been", "you", "the"],
            "can": ["you", "i", "we", "be", "do"],
            "do": ["you", "not", "the", "it", "that"],
            "it": ["is", "was", "will", "would", "should"],
            "this": ["is", "was", "will", "one", "weekend"],
            "that": ["is", "was", "the", "would", "i"],
            "we": ["are", "can", "will", "should", "need"],
            "of": ["the", "course", "my", "a", "them"],
            "and": ["the", "i", "then", "we", "a"],
            "on": ["the", "my", "a", "it", "your"],
            "in": ["the", "a", "my", "this", "order"],
            "for": ["the", "a", "you", "me", "your"],
            "my": ["friend", "name", "phone", "family", "house"],
            "see": ["you", "the", "if", "what", "that"],
            "let": ["me", "us", "them", "it"],
            "please": ["let", "send", "call", "find"],
            "hello": ["there", "everyone"],
            "hi": ["there", "everyone"],
            "no": ["problem", "worries", "i", "one"],
            "yes": ["i", "please", "it", "of"],
            "ok": ["i", "thanks", "sounds", "let"],
            "okay": ["i", "thanks", "sounds", "let"],
            "going": ["to", "out", "home", "back"],
            "want": ["to", "a", "some", "the"],
            "need": ["to", "a", "some", "the"],
        ],
        contractions: [
            "im": "I'm", "ive": "I've",
            "dont": "don't", "doesnt": "doesn't", "didnt": "didn't",
            "isnt": "isn't", "wasnt": "wasn't", "arent": "aren't", "werent": "weren't",
            "havent": "haven't", "hasnt": "hasn't", "hadnt": "hadn't",
            "cant": "can't", "couldnt": "couldn't", "wont": "won't",
            "wouldnt": "wouldn't", "shouldnt": "shouldn't", "mustnt": "mustn't",
            "youre": "you're", "youve": "you've", "youll": "you'll", "youd": "you'd",
            "theyre": "they're", "theyve": "they've", "theyll": "they'll", "theyd": "they'd",
            "weve": "we've",
            "hes": "he's", "shes": "she's",
            "thats": "that's", "whats": "what's", "whos": "who's", "wheres": "where's",
            "theres": "there's", "heres": "here's", "hows": "how's",
            "couldve": "could've", "wouldve": "would've", "shouldve": "should've",
        ],
        commonWords: [
            "a", "able", "about", "above", "after", "again", "against", "all", "almost",
            "alone", "along", "already", "also", "although", "always", "am", "among",
            "an", "and", "another", "answer", "any", "anyone", "anything", "are", "around",
            "as", "ask", "at", "away", "back", "bad", "be", "because", "become", "been",
            "before", "began", "begin", "behind", "being", "believe", "best", "better",
            "between", "big", "both", "bring", "business", "but", "buy", "by", "call",
            "came", "can", "cannot", "car", "care", "change", "child", "city", "close",
            "come", "company", "could", "country", "course", "day", "days", "did", "different",
            "do", "does", "done", "down", "during", "each", "early", "easy", "eat", "end",
            "enough", "even", "evening", "ever", "every", "everyone", "everything", "example",
            "eyes", "face", "fact", "family", "far", "feel", "feeling", "few", "find", "fine",
            "first", "follow", "food", "for", "found", "free", "friend", "friends", "from",
            "full", "fun", "general", "get", "give", "go", "going", "good", "got", "great",
            "group", "had", "hand", "happen", "happy", "hard", "has", "have", "he", "head",
            "hear", "heard", "hello", "help", "her", "here", "high", "him", "himself", "his",
            "home", "hope", "house", "how", "however", "i", "idea", "if", "important", "in",
            "into", "is", "it", "its", "just", "keep", "kind", "knew", "know", "land", "large",
            "last", "late", "later", "learn", "leave", "left", "less", "let", "life", "light",
            "like", "line", "little", "live", "long", "look", "lot", "love", "made", "make",
            "man", "many", "may", "maybe", "me", "mean", "might", "mind", "money", "more",
            "morning", "most", "mother", "move", "much", "must", "my", "name", "near", "need",
            "never", "new", "next", "nice", "night", "no", "not", "nothing", "now", "number",
            "of", "off", "often", "old", "on", "once", "one", "only", "open", "or", "order",
            "other", "our", "out", "over", "own", "part", "people", "perfect", "perhaps",
            "person", "place", "play", "please", "point", "possible", "probably", "problem",
            "put", "question", "quite", "rather", "really", "reason", "remember", "right",
            "room", "run", "said", "same", "saw", "say", "school", "second", "see", "seem",
            "seen", "send", "set", "several", "she", "should", "show", "side", "since",
            "small", "so", "some", "someone", "something", "sometimes", "soon", "sorry",
            "sound", "special", "start", "started", "still", "stop", "story", "such", "sure",
            "system", "take", "talk", "tell", "than", "thank", "thanks", "that", "the",
            "their", "them", "then", "there", "these", "they", "thing", "things", "think",
            "this", "those", "though", "thought", "three", "through", "time", "to", "today",
            "together", "told", "tomorrow", "tonight", "too", "took", "town", "true", "try",
            "turn", "two", "under", "understand", "until", "up", "upon", "us", "use", "used",
            "very", "wait", "walk", "want", "was", "watch", "water", "way", "we", "week",
            "well", "went", "were", "what", "when", "where", "whether", "which", "while",
            "white", "who", "whole", "why", "will", "with", "within", "without", "woman",
            "word", "words", "work", "world", "would", "write", "wrong", "year", "years",
            "yes", "yet", "you", "young", "your", "yourself",
        ])
}

// MARK: - French

private extension LanguageHeuristics {
    static let french = LanguageHeuristics(
        sentenceStarters: ["Je", "C'est", "Le"],
        commonFallback: ["de", "la", "et"],
        bigrams: [
            "je": ["suis", "vais", "ne", "pense", "veux"],
            "c'est": ["un", "une", "le", "la", "pas"],
            "le": ["plus", "même", "premier", "monde", "temps"],
            "la": ["plus", "première", "même", "vie", "maison"],
            "de": ["la", "le", "plus", "rien", "ce"],
            "tu": ["es", "as", "veux", "peux", "vas"],
            "vous": ["êtes", "avez", "pouvez", "voulez"],
            "il": ["est", "y", "a", "faut", "ne"],
            "elle": ["est", "a", "ne", "va"],
            "nous": ["sommes", "avons", "allons", "pouvons"],
            "pour": ["la", "le", "les", "un", "vous"],
            "dans": ["la", "le", "les", "un", "ce"],
            "avec": ["le", "la", "les", "un", "moi"],
            "est": ["un", "une", "le", "la", "pas"],
            "sur": ["le", "la", "les", "un"],
            "pas": ["de", "le", "la", "encore"],
            "plus": ["de", "que", "tard", "tôt"],
            "bonjour": ["à", "tout"],
            "merci": ["beaucoup", "à", "pour"],
            "très": ["bien", "bon", "content"],
            "bien": ["sûr", "que", "fait"],
            "oui": ["je", "bien", "merci"],
            "non": ["je", "merci", "pas"],
            "j'ai": ["un", "une", "été", "pas", "besoin"],
        ],
        contractions: [
            "cest": "c'est", "jai": "j'ai", "jaime": "j'aime",
            "dun": "d'un", "quil": "qu'il", "quon": "qu'on",
        ],
        commonWords: [
            "le", "la", "les", "un", "une", "des", "de", "du", "et", "à", "il", "elle",
            "je", "tu", "nous", "vous", "ils", "elles", "ce", "cette", "ces", "mon", "ma",
            "mes", "ton", "ta", "tes", "son", "sa", "ses", "notre", "votre", "leur", "leurs",
            "que", "qui", "quoi", "dont", "où", "quand", "comment", "pourquoi", "est", "sont",
            "suis", "es", "sommes", "êtes", "être", "avoir", "ai", "as", "avons", "avez",
            "ont", "fait", "faire", "va", "vais", "vas", "allons", "allez", "vont", "aller",
            "peut", "peux", "pouvons", "pouvez", "peuvent", "pouvoir", "veut", "veux",
            "voulons", "voulez", "veulent", "vouloir", "dit", "dire", "voir", "vois", "voit",
            "savoir", "sais", "sait", "plus", "moins", "très", "bien", "mal", "aussi",
            "encore", "déjà", "toujours", "jamais", "souvent", "ici", "là", "oui", "non",
            "merci", "bonjour", "salut", "pour", "par", "sur", "sous", "dans", "avec", "sans",
            "chez", "vers", "entre", "pendant", "avant", "après", "mais", "ou", "donc", "car",
            "si", "comme", "parce", "alors", "beaucoup", "peu", "tout", "tous", "toute",
            "toutes", "rien", "chose", "temps", "jour", "jours", "fois", "homme", "femme",
            "gens", "vie", "monde", "main", "eau", "nom", "ami", "amie", "maison", "travail",
            "bon", "bonne", "grand", "grande", "petit", "petite", "nouveau", "nouvelle",
            "premier", "première", "dernier", "même", "autre", "autres", "chaque", "quelque",
            "quelques",
        ])
}

// MARK: - Spanish

private extension LanguageHeuristics {
    static let spanish = LanguageHeuristics(
        sentenceStarters: ["El", "La", "No"],
        commonFallback: ["de", "la", "que"],
        bigrams: [
            "yo": ["soy", "tengo", "quiero", "no", "voy"],
            "el": ["que", "más", "mismo", "mundo", "día"],
            "la": ["que", "más", "misma", "vida", "casa"],
            "de": ["la", "los", "las", "que", "un"],
            "que": ["no", "el", "la", "se", "te"],
            "no": ["es", "se", "me", "te", "hay"],
            "es": ["un", "una", "el", "la", "que"],
            "está": ["en", "bien", "muy", "aquí"],
            "tú": ["eres", "tienes", "quieres", "puedes"],
            "qué": ["es", "tal", "hora", "pasa"],
            "cómo": ["estás", "es", "se", "te"],
            "por": ["el", "la", "favor", "que", "eso"],
            "para": ["el", "la", "que", "ti", "mí"],
            "con": ["el", "la", "un", "los", "mi"],
            "en": ["el", "la", "los", "un", "este"],
            "gracias": ["por", "a"],
            "muy": ["bien", "bueno", "buena", "mal"],
            "hola": ["a", "qué"],
            "sí": ["por", "claro", "está"],
            "tengo": ["que", "un", "una", "ganas"],
            "voy": ["a"],
            "vamos": ["a"],
        ],
        contractions: [:],
        commonWords: [
            "el", "la", "los", "las", "un", "una", "unos", "unas", "de", "del", "a", "al",
            "y", "e", "o", "u", "que", "qué", "quien", "quién", "como", "cómo", "cuando",
            "cuándo", "donde", "dónde", "por", "para", "con", "sin", "sobre", "entre",
            "hacia", "hasta", "desde", "en", "es", "son", "soy", "eres", "somos", "ser",
            "estar", "está", "están", "estoy", "estás", "estamos", "hay", "tener", "tengo",
            "tienes", "tiene", "tenemos", "tienen", "hacer", "hago", "hace", "hacemos",
            "hacen", "ir", "voy", "vas", "va", "vamos", "van", "poder", "puedo", "puede",
            "podemos", "pueden", "querer", "quiero", "quieres", "quiere", "queremos",
            "quieren", "decir", "digo", "dice", "ver", "veo", "ve", "saber", "sé", "sabe",
            "más", "menos", "muy", "bien", "mal", "también", "todavía", "ya", "siempre",
            "nunca", "aquí", "allí", "sí", "no", "quizás", "gracias", "hola", "adiós", "pero",
            "porque", "si", "así", "entonces", "mucho", "mucha", "muchos", "muchas", "poco",
            "todo", "todos", "toda", "todas", "nada", "algo", "cosa", "cosas", "tiempo",
            "día", "días", "vez", "veces", "hombre", "mujer", "gente", "vida", "mundo",
            "mano", "agua", "nombre", "amigo", "amiga", "casa", "trabajo", "bueno", "buena",
            "malo", "grande", "pequeño", "pequeña", "nuevo", "nueva", "primero", "primera",
            "último", "mismo", "misma", "otro", "otra", "otros", "otras", "cada", "alguno",
            "alguna", "mi", "tu", "su", "nuestro", "vuestro", "me", "te", "se", "nos", "le",
            "les", "lo",
        ])
}

// MARK: - German

private extension LanguageHeuristics {
    static let german = LanguageHeuristics(
        sentenceStarters: ["Ich", "Der", "Die"],
        commonFallback: ["der", "die", "und"],
        bigrams: [
            "ich": ["bin", "habe", "will", "kann", "muss"],
            "der": ["mann", "tag", "beste", "erste", "neue"],
            "die": ["frau", "zeit", "beste", "erste", "neue"],
            "das": ["ist", "war", "beste", "erste", "haus"],
            "ist": ["ein", "eine", "das", "der", "nicht"],
            "du": ["bist", "hast", "kannst", "willst", "musst"],
            "wir": ["sind", "haben", "können", "wollen", "müssen"],
            "sie": ["sind", "haben", "ist", "können", "wollen"],
            "es": ["ist", "war", "gibt", "geht", "wird"],
            "ein": ["mann", "tag", "jahr", "paar", "bisschen"],
            "eine": ["frau", "zeit", "frage", "idee"],
            "nicht": ["mehr", "so", "nur", "ganz", "wahr"],
            "und": ["ich", "die", "der", "das", "dann"],
            "was": ["ist", "war", "machst", "soll"],
            "wie": ["geht", "ist", "viel", "lange"],
            "wo": ["ist", "bist", "sind"],
            "für": ["die", "den", "das", "dich", "mich"],
            "mit": ["dem", "der", "den", "dir", "mir"],
            "auf": ["dem", "der", "den", "die", "das"],
            "in": ["der", "die", "das", "dem", "den"],
            "danke": ["für", "schön", "dir"],
            "hallo": ["zusammen"],
            "sehr": ["gut", "schön", "viel"],
            "ja": ["ich", "das", "klar"],
            "nein": ["ich", "danke", "das"],
        ],
        contractions: [:],
        commonWords: [
            "der", "die", "das", "den", "dem", "des", "ein", "eine", "einen", "einem",
            "einer", "eines", "und", "oder", "aber", "denn", "sondern", "ich", "du", "er",
            "sie", "es", "wir", "ihr", "mich", "dich", "sich", "uns", "euch", "mir", "dir",
            "ihm", "mein", "dein", "sein", "unser", "euer", "ist", "sind", "bin", "bist",
            "war", "waren", "haben", "habe", "hast", "hat", "hatte", "hatten", "werden",
            "wird", "wurde", "kann", "kannst", "können", "will", "willst", "wollen", "muss",
            "musst", "müssen", "soll", "sollen", "darf", "dürfen", "mag", "möchte", "machen",
            "mache", "macht", "gehen", "gehe", "geht", "kommen", "komme", "kommt", "sehen",
            "sehe", "sieht", "wissen", "weiß", "sagen", "sagt", "nicht", "kein", "keine",
            "nur", "auch", "schon", "noch", "immer", "nie", "oft", "hier", "da", "dort",
            "jetzt", "dann", "ja", "nein", "vielleicht", "danke", "hallo", "bitte", "für",
            "mit", "von", "zu", "aus", "bei", "nach", "über", "unter", "vor", "hinter",
            "zwischen", "ohne", "gegen", "um", "durch", "an", "auf", "sehr", "mehr", "viel",
            "wenig", "gut", "schlecht", "groß", "klein", "neu", "alt", "erste", "letzte",
            "gleich", "andere", "jeder", "alle", "etwas", "nichts", "ding", "zeit", "tag",
            "jahr", "mensch", "frau", "mann", "leben", "welt", "hand", "wasser", "name",
            "freund", "haus", "arbeit", "was", "wer", "wie", "wo", "wann", "warum", "weil",
            "wenn", "als",
        ])
}

// MARK: - Italian

private extension LanguageHeuristics {
    static let italian = LanguageHeuristics(
        sentenceStarters: ["Io", "Il", "La"],
        commonFallback: ["di", "la", "che"],
        bigrams: [
            "io": ["sono", "ho", "voglio", "non", "vado"],
            "il": ["più", "primo", "mondo", "tempo", "giorno"],
            "la": ["più", "prima", "vita", "casa", "mia"],
            "di": ["più", "un", "una", "te", "me"],
            "che": ["non", "cosa", "il", "la", "ti"],
            "non": ["è", "so", "ho", "mi", "ci"],
            "è": ["un", "una", "il", "la", "molto"],
            "tu": ["sei", "hai", "vuoi", "puoi"],
            "per": ["il", "la", "un", "te", "me"],
            "con": ["il", "la", "un", "me", "te"],
            "in": ["un", "una", "questo", "casa"],
            "cosa": ["è", "fai", "vuoi"],
            "come": ["stai", "va", "è"],
            "grazie": ["per", "mille", "a"],
            "ciao": ["a"],
            "sì": ["certo", "grazie"],
            "molto": ["bene", "buono", "bella"],
            "ho": ["un", "una", "bisogno", "fame"],
            "sono": ["un", "una", "qui", "molto"],
        ],
        contractions: [:],
        commonWords: [
            "il", "lo", "la", "i", "gli", "le", "un", "uno", "una", "di", "del", "della",
            "dei", "delle", "a", "al", "alla", "ai", "da", "dal", "in", "nel", "nella",
            "con", "su", "sul", "per", "tra", "fra", "e", "o", "ma", "che", "chi", "cosa",
            "come", "quando", "dove", "perché", "io", "tu", "lui", "lei", "noi", "voi",
            "loro", "mi", "ti", "ci", "vi", "si", "me", "te", "mio", "mia", "tuo", "tua",
            "suo", "sua", "nostro", "vostro", "è", "sono", "sei", "siamo", "siete", "essere",
            "ho", "hai", "ha", "abbiamo", "avete", "hanno", "avere", "fare", "faccio", "fa",
            "fanno", "andare", "vado", "va", "andiamo", "vanno", "potere", "posso", "può",
            "possiamo", "volere", "voglio", "vuoi", "vuole", "dire", "dico", "dice", "vedere",
            "vedo", "vede", "sapere", "so", "sa", "più", "meno", "molto", "poco", "bene",
            "male", "anche", "ancora", "già", "sempre", "mai", "qui", "lì", "sì", "no",
            "forse", "grazie", "ciao", "prego", "non", "se", "perché", "quindi", "allora",
            "tutto", "tutti", "tutta", "tutte", "niente", "cose", "tempo", "giorno", "giorni",
            "volta", "volte", "uomo", "donna", "gente", "vita", "mondo", "mano", "acqua",
            "nome", "amico", "amica", "casa", "lavoro", "buono", "buona", "grande", "piccolo",
            "piccola", "nuovo", "nuova", "primo", "prima", "ultimo", "stesso", "altro",
            "altra", "ogni", "qualche",
        ])
}

// MARK: - Portuguese

private extension LanguageHeuristics {
    static let portuguese = LanguageHeuristics(
        sentenceStarters: ["Eu", "O", "A"],
        commonFallback: ["de", "que", "e"],
        bigrams: [
            "eu": ["sou", "tenho", "quero", "não", "vou"],
            "o": ["que", "mais", "mesmo", "mundo", "dia"],
            "a": ["que", "mais", "mesma", "vida", "casa"],
            "de": ["um", "uma", "que", "mais", "novo"],
            "que": ["não", "eu", "o", "a", "te"],
            "não": ["é", "sei", "tem", "vou", "posso"],
            "é": ["um", "uma", "o", "a", "muito"],
            "você": ["é", "tem", "quer", "pode", "vai"],
            "para": ["o", "a", "que", "você", "mim"],
            "com": ["o", "a", "um", "você", "isso"],
            "em": ["um", "uma", "casa", "que"],
            "como": ["você", "está", "é", "vai"],
            "obrigado": ["por", "pela"],
            "oi": ["tudo"],
            "sim": ["claro", "por"],
            "muito": ["bem", "bom", "boa", "obrigado"],
            "tenho": ["que", "um", "uma"],
            "vou": ["te", "para"],
        ],
        contractions: [:],
        commonWords: [
            "o", "a", "os", "as", "um", "uma", "uns", "umas", "de", "do", "da", "dos", "das",
            "em", "no", "na", "nos", "nas", "por", "para", "com", "sem", "sobre", "entre",
            "até", "desde", "e", "ou", "mas", "que", "quem", "qual", "como", "quando", "onde",
            "porque", "eu", "tu", "você", "ele", "ela", "nós", "vós", "eles", "elas", "me",
            "te", "se", "lhe", "meu", "minha", "teu", "tua", "seu", "sua", "nosso", "vosso",
            "é", "são", "sou", "somos", "ser", "estar", "está", "estão", "estou", "há",
            "ter", "tenho", "tem", "temos", "têm", "fazer", "faço", "faz", "fazem", "ir",
            "vou", "vai", "vamos", "vão", "poder", "posso", "pode", "podemos", "querer",
            "quero", "quer", "queremos", "dizer", "digo", "diz", "ver", "vejo", "vê", "saber",
            "sei", "sabe", "mais", "menos", "muito", "pouco", "bem", "mal", "também", "ainda",
            "já", "sempre", "nunca", "aqui", "ali", "sim", "não", "talvez", "obrigado", "oi",
            "olá", "tchau", "se", "porque", "então", "assim", "tudo", "todos", "toda", "todas",
            "nada", "algo", "coisa", "coisas", "tempo", "dia", "dias", "vez", "vezes", "homem",
            "mulher", "gente", "vida", "mundo", "mão", "água", "nome", "amigo", "amiga",
            "casa", "trabalho", "bom", "boa", "grande", "pequeno", "pequena", "novo", "nova",
            "primeiro", "primeira", "último", "mesmo", "mesma", "outro", "outra", "cada",
            "algum", "alguma",
        ])
}

// MARK: - Russian

private extension LanguageHeuristics {
    static let russian = LanguageHeuristics(
        sentenceStarters: ["Я", "Это", "Не"],
        commonFallback: ["и", "в", "не"],
        bigrams: [
            "я": ["не", "хочу", "думаю", "буду", "знаю"],
            "это": ["не", "был", "была", "было", "очень"],
            "не": ["знаю", "хочу", "могу", "буду", "так"],
            "в": ["этом", "том", "доме", "городе"],
            "на": ["это", "том", "этом", "работе"],
            "ты": ["не", "был", "можешь", "хочешь", "знаешь"],
            "мы": ["не", "будем", "можем", "хотим"],
            "он": ["не", "был", "будет", "может"],
            "она": ["не", "была", "будет", "может"],
            "что": ["это", "ты", "не", "за", "то"],
            "как": ["дела", "ты", "это", "там"],
            "у": ["меня", "тебя", "нас", "него"],
            "с": ["тобой", "ним", "ней", "нами"],
            "для": ["тебя", "меня", "нас", "этого"],
            "спасибо": ["за", "большое"],
            "привет": ["как"],
            "да": ["я", "конечно", "это"],
            "очень": ["хорошо", "много", "рад"],
            "меня": ["есть", "зовут", "нет"],
            "тебя": ["есть", "зовут"],
        ],
        contractions: [:],
        commonWords: [
            "и", "в", "не", "на", "я", "что", "тот", "быть", "с", "он", "а", "по", "это",
            "она", "этот", "к", "но", "они", "мы", "как", "из", "у", "который", "то", "за",
            "свой", "весь", "год", "от", "так", "о", "для", "ты", "же", "все", "тебя", "меня",
            "было", "вот", "ещё", "нет", "ему", "теперь", "когда", "даже", "ну", "вдруг",
            "ли", "если", "уже", "или", "ни", "был", "него", "до", "вас", "опять", "уж",
            "вам", "ведь", "там", "потом", "себя", "ничего", "ей", "может", "тут", "где",
            "есть", "надо", "ней", "их", "чем", "была", "сам", "чтоб", "без", "будто",
            "человек", "чего", "раз", "тоже", "себе", "под", "будет", "тогда", "кто",
            "говорил", "того", "потому", "этого", "какой", "совсем", "ним", "здесь", "этом",
            "один", "почти", "мой", "тем", "чтобы", "нее", "кажется", "сейчас", "были",
            "куда", "зачем", "всех", "никогда", "можно", "при", "наконец", "два", "об",
            "другой", "хорошо", "после", "над", "больше", "через", "эти", "нас", "про",
            "всего", "них", "какая", "много", "разве", "сказал", "три", "эту", "моя",
            "впрочем", "свою", "этой", "перед", "иногда", "лучше", "чуть", "том", "нельзя",
            "такой", "им", "более", "всегда", "конечно", "всю", "между", "спасибо", "привет",
            "да",
        ])
}
