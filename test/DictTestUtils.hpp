﻿/*
 * Open Chinese Convert
 *
 * Copyright 2010-2013 BYVoid <byvoid@byvoid.com>
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#pragma once

#include "Conversion.hpp"
#include "DartsDict.hpp"
#include "Dict.hpp"
#include "DictGroup.hpp"
#include "TestUtils.hpp"
#include "TextDict.hpp"

#if defined(_MSC_VER) && _MSC_VER > 1310
// Visual C++ 2005 and later require the source files in UTF-8, and all strings
// to be encoded as wchar_t otherwise the strings will be converted into the
// local multibyte encoding and cause errors. To use a wchar_t as UTF-8, these
// strings then need to be convert back to UTF-8. This function is just a rough
// example of how to do this.
# include <Windows.h>
# define utf8(str) ConvertToUTF8(L ## str)
const char* ConvertToUTF8(const wchar_t* pStr) {
  static char szBuf[1024];
  WideCharToMultiByte(CP_UTF8, 0, pStr, -1, szBuf, sizeof(szBuf), NULL, NULL);
  return szBuf;
}

#else // if defined(_MSC_VER) && _MSC_VER > 1310
// Visual C++ 2003 and gcc will use the string literals as is, so the files
// should be saved as UTF-8. gcc requires the files to not have a UTF-8 BOM.
# define utf8(str) str
#endif // if defined(_MSC_VER) && _MSC_VER > 1310

namespace opencc {
  class DictTestUtils {
    public:
      static TextDictPtr CreateTextDictForText() {
        vector<DictEntry> lexicon;
        lexicon.push_back(DictEntry("BYVoid", "byv"));
        lexicon.push_back(DictEntry("zigzagzig", "zag"));
        lexicon.push_back(DictEntry(utf8("積羽沉舟"), utf8("羣輕折軸")));
        lexicon.push_back(DictEntry(utf8("清"), "Tsing"));
        lexicon.push_back(DictEntry(utf8("清華"), "Tsinghua"));
        lexicon.push_back(DictEntry(utf8("清華大學"), "TsinghuaUniversity"));
        TextDictPtr textDict(new TextDict(lexicon));
        return textDict;
      }

      static DictPtr CreateDictForCharacters() {
        vector<DictEntry> lexicon;
        lexicon.push_back(DictEntry(utf8("后"),
                                    vector<string>{ utf8("后"), utf8("後") }));
        lexicon.push_back(DictEntry(utf8("发"),
                                    vector<string>{ utf8("發"), utf8("髮") }));
        lexicon.push_back(DictEntry(utf8("干"),
                                    vector<string>{ utf8("幹"), utf8("乾"),
                                                    utf8("干") }));
        lexicon.push_back(DictEntry(utf8("里"),
                                    vector<string>{ utf8("裏"), utf8("里") }));
        TextDictPtr textDict(new TextDict(lexicon));
        return textDict;
      }

      static DictPtr CreateDictForPhrases() {
        vector<DictEntry> lexicon;
        lexicon.push_back(DictEntry(utf8("太后"), utf8("太后")));
        lexicon.push_back(DictEntry(utf8("头发"), utf8("頭髮")));
        lexicon.push_back(DictEntry(utf8("干燥"), utf8("乾燥")));
        TextDictPtr textDict(new TextDict(lexicon));

        DartsDictPtr dartsDict = DartsDict::NewFromDict(*textDict.get());
        return dartsDict;
      }

      static DictGroupPtr CreateDictGroupForConversion() {
        DictPtr phrasesDict = CreateDictForPhrases();
        DictPtr charactersDict = CreateDictForCharacters();
        list<DictPtr> dicts;
        dicts.push_back(phrasesDict);
        dicts.push_back(charactersDict);
        DictGroupPtr dictGroup(new DictGroup(dicts));
        return dictGroup;
      }

      static DictPtr CreateDictForTaiwanVariants() {
        vector<DictEntry> lexicon;
        lexicon.push_back(DictEntry(utf8("裏"), utf8("裡")));
        TextDictPtr textDict(new TextDict(lexicon));
        return textDict;
      }

      static void TestDict(DictPtr dict) {
        Optional<DictEntry> entry;
        entry = dict->MatchPrefix("BYVoid");
        AssertTrue(!entry.IsNull());
        AssertEquals("BYVoid", entry.Get().key);
        AssertEquals("byv", entry.Get().GetDefault());

        entry = dict->MatchPrefix("BYVoid123");
        AssertTrue(!entry.IsNull());
        AssertEquals("BYVoid", entry.Get().key);
        AssertEquals("byv", entry.Get().GetDefault());

        entry = dict->MatchPrefix(utf8("積羽沉舟"));
        AssertTrue(!entry.IsNull());
        AssertEquals(utf8("積羽沉舟"), entry.Get().key);
        AssertEquals(utf8("羣輕折軸"), entry.Get().GetDefault());

        entry = dict->MatchPrefix("Unknown");
        AssertTrue(entry.IsNull());

        const vector<DictEntry> matches =
          dict->MatchAllPrefixes(utf8("清華大學計算機系"));
        AssertEquals(3, matches.size());
        AssertEquals(utf8("清華大學"), matches.at(0).key);
        AssertEquals("TsinghuaUniversity", matches.at(0).GetDefault());
        AssertEquals(utf8("清華"), matches.at(1).key);
        AssertEquals("Tsinghua", matches.at(1).GetDefault());
        AssertEquals(utf8("清"), matches.at(2).key);
        AssertEquals("Tsing", matches.at(2).GetDefault());
      }
  };
}
