"""Search words people type (English / Hinglish) -> the Hindi product names shops use."""

# i18n note: keys are lowercase Latin; values are substrings of Hindi product names.
SYNONYMS = {
    "tomato": ["टमाटर"], "tamatar": ["टमाटर"], "potato": ["आलू"], "aloo": ["आलू"], "alu": ["आलू"],
    "onion": ["प्याज़", "प्याज"], "pyaz": ["प्याज़", "प्याज"], "pyaj": ["प्याज़", "प्याज"],
    "spinach": ["पालक"], "palak": ["पालक"], "okra": ["भिंडी"], "bhindi": ["भिंडी"], "cabbage": ["गोभी"], "gobhi": ["गोभी"], "gobi": ["गोभी"],
    "carrot": ["गाजर"], "gajar": ["गाजर"], "peas": ["मटर"], "matar": ["मटर"], "cucumber": ["खीरा"], "kheera": ["खीरा"],
    "chilli": ["मिर्च"], "mirch": ["मिर्च"], "coriander": ["धनिया"], "dhaniya": ["धनिया"], "ginger": ["अदरक"], "adrak": ["अदरक"],
    "garlic": ["लहसुन"], "lahsun": ["लहसुन"], "lemon": ["नींबू"], "nimbu": ["नींबू"], "brinjal": ["बैंगन"], "baingan": ["बैंगन"],
    "gourd": ["लौकी", "तोरई"], "lauki": ["लौकी"], "mushroom": ["मशरूम"], "capsicum": ["शिमला मिर्च"],
    "apple": ["सेब"], "seb": ["सेब"], "banana": ["केला"], "kela": ["केला"], "mango": ["आम"], "aam": ["आम"],
    "grapes": ["अंगूर"], "angoor": ["अंगूर"], "orange": ["संतरा", "मौसमी"], "santra": ["संतरा"], "mosambi": ["मौसमी"],
    "papaya": ["पपीता"], "papita": ["पपीता"], "pomegranate": ["अनार"], "anar": ["अनार"], "watermelon": ["तरबूज़", "तरबूज"],
    "guava": ["अमरूद"], "amrood": ["अमरूद"], "kiwi": ["कीवी"], "pear": ["नाशपाती"], "chikoo": ["चीकू"],
    "milk": ["दूध"], "doodh": ["दूध"], "dudh": ["दूध"], "paneer": ["पनीर"], "curd": ["दही"], "dahi": ["दही"], "ghee": ["घी"],
    "butter": ["मक्खन"], "makhan": ["मक्खन"], "lassi": ["लस्सी"], "buttermilk": ["छाछ"], "chhach": ["छाछ"], "khoya": ["खोया"],
    "flour": ["आटा"], "atta": ["आटा"], "rice": ["चावल"], "chawal": ["चावल"], "dal": ["दाल"], "oil": ["तेल"], "tel": ["तेल"],
    "sugar": ["चीनी"], "cheeni": ["चीनी"], "chini": ["चीनी"], "tea": ["चाय"], "chai": ["चाय"], "besan": ["बेसन"], "suji": ["सूजी"],
    "poha": ["पोहा"], "rajma": ["राजमा"], "chana": ["चना"], "maggi": ["मैगी"], "noodles": ["मैगी"], "honey": ["शहद"], "shahad": ["शहद"],
    "almond": ["बादाम"], "badam": ["बादाम"], "cashew": ["काजू"], "kaju": ["काजू"], "raisin": ["किशमिश"], "kishmish": ["किशमिश"],
    "bread": ["ब्रेड"], "cake": ["केक"], "biscuit": ["बिस्कुट"], "cookies": ["कुकीज़"], "rusk": ["रस्क"], "pav": ["पाव"], "bun": ["बन"],
    "namkeen": ["नमकीन", "भुजिया", "मिक्सचर"], "bhujia": ["भुजिया"], "samosa": ["समोसा"], "kachori": ["कचौड़ी"], "jalebi": ["जलेबी"],
    "sweets": ["बर्फ़ी", "गुलाब जामुन", "रसगुल्ला", "सोन पापड़ी"], "mithai": ["बर्फ़ी", "गुलाब जामुन", "रसगुल्ला"],
    "juice": ["जूस"], "water": ["पानी", "वॉटर"], "cold drink": ["कोल्ड ड्रिंक"], "coconut": ["नारियल"],
    "chicken": ["चिकन"], "egg": ["अंडे"], "eggs": ["अंडे"], "anda": ["अंडे"], "fish": ["मछली"], "machli": ["मछली"], "mutton": ["मटन"],
    "soap": ["साबुन"], "sabun": ["साबुन"], "detergent": ["डिटर्जेंट"], "shampoo": ["शैम्पू"], "toothpaste": ["टूथपेस्ट"],
    "pickle": ["अचार"], "achar": ["अचार"], "papad": ["पापड़"], "jaggery": ["गुड़"], "gud": ["गुड़"],
}


def search_terms(q):
    """The typed text plus any Hindi names it stands for."""
    q = q.strip()
    terms = {q}
    lower = q.lower()
    for word, hindi in SYNONYMS.items():
        if word == lower or (len(lower) >= 4 and word.startswith(lower)) or word in lower.split():
            terms.update(hindi)
    return terms
