/*
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

#include "Common.hpp"
#include "SerializableDict.hpp"

namespace opencc {
  class OPENCC_EXPORT TextDict : public SerializableDict {
    public:
      TextDict(const vector<DictEntry>& _lexicon);
      virtual ~TextDict();
      virtual size_t KeyMaxLength() const;
      virtual Optional<DictEntry> Match(const char* word) const;
      virtual vector<DictEntry> GetLexicon() const;
      virtual void SerializeToFile(FILE* fp) const;
      static TextDictPtr NewFromDict(const Dict& dict);
      static TextDictPtr NewFromFile(FILE* fp);
    private:
      const size_t maxLength;
      const vector<DictEntry> lexicon;
  };
}
