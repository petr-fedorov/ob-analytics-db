// Copyright (C) 2019 Petr Fedorov <petr.fedorov@phystech.edu>

// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation,  version 2 of the License

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License along
// with this program; if not, write to the Free Software Foundation, Inc.,
// 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

#ifndef SPREAD_H
#define SPREAD_H

#ifdef __cplusplus
extern "C" {
#endif // __cplusplus

#include "postgres.h"
#include "utils/timestamp.h"
#include "funcapi.h"
#include "executor/spi.h"
#include "catalog/pg_type_d.h"

#ifdef __cplusplus
}
#endif // __cplusplus

#include <vector>

namespace obad {
    using price = long double;
    using amount = long double;

    class level2_impl;	// is supposed to have an SPI-aware new and delete operators ...

    class level2 {
	  public:
		level2() {
		    p_impl = nullptr;
		};

		level2(TimestampTz, price, amount);

		level2(level2&& m);

		~level2(); 

		char side();

		bool operator < (const level2 &);

	  private:
		level2_impl *p_impl;
    };
    
    struct level1 {
	  price best_bid_price;
	  amount best_bid_qty;
	  price best_ask_price;
	  amount best_ask_qty;
	  TimestampTz microtimestamp;

	  level1() : best_bid_price(-1), best_bid_qty(-1), best_ask_price(-1), best_ask_qty(-1), microtimestamp(0) {};

	  HeapTuple to_heap_tuple(AttInMetadata *, int32, int32);

	  bool operator == (const level1 &c) { return (best_bid_price == c.best_bid_price) && (best_bid_qty == c.best_bid_qty) && (best_ask_price == c.best_ask_price) && (best_ask_qty == c.best_ask_qty); };
	  bool operator != (const level1 &c) { return !(*this == c); };
    };



    class level2_episode {
	  public:
		static const long unsigned NULL_FREQ = 0;
		level2_episode();
		level2_episode(Datum start_time, Datum end_time, Datum pair_id, Datum exchange_id, Datum frequency);
		std::vector<level2> initial();
		std::vector<level2> next();
		TimestampTz microtimestamp();
	  private:
		static constexpr const char * const INITIAL = "initial";
		static constexpr const char * const CURSOR ="level2";
		Portal portal;
    };

    class depth {
	  public:
		level1 spread();
		level1 update(std::vector<level2>); 
		void * operator new(size_t s);
		void operator delete(void *p, size_t s);

	  private:
		TimestampTz episode;
    };
		
}



#endif
