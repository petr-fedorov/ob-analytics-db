-- Copyright (C) 2019 Petr Fedorov <petr.fedorov@phystech.edu>

-- This program is free software; you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation,  version 2 of the License

-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.

-- You should have received a copy of the GNU General Public License along
-- with this program; if not, write to the Free Software Foundation, Inc.,
-- 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

--
-- PostgreSQL database dump
--

-- Dumped from database version 11.6
-- Dumped by pg_dump version 11.6

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: bitfinex; Type: SCHEMA; Schema: -; Owner: ob-analytics
--

CREATE SCHEMA bitfinex;


ALTER SCHEMA bitfinex OWNER TO "ob-analytics";

--
-- Name: _tableoid_ctid; Type: TYPE; Schema: bitfinex; Owner: ob-analytics
--

CREATE TYPE bitfinex._tableoid_ctid AS (
	tableoid oid,
	ctid tid
);


ALTER TYPE bitfinex._tableoid_ctid OWNER TO "ob-analytics";

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: transient_raw_book_events; Type: TABLE; Schema: bitfinex; Owner: ob-analytics
--

CREATE TABLE bitfinex.transient_raw_book_events (
    exchange_timestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    pair_id smallint NOT NULL,
    local_timestamp timestamp with time zone,
    channel_id integer,
    episode_timestamp timestamp with time zone NOT NULL,
    event_no integer,
    bl integer
);


ALTER TABLE bitfinex.transient_raw_book_events OWNER TO "ob-analytics";

--
-- Name: _diff_order_books(bitfinex.transient_raw_book_events[], bitfinex.transient_raw_book_events[]); Type: FUNCTION; Schema: bitfinex; Owner: ob-analytics
--

CREATE FUNCTION bitfinex._diff_order_books(p_order_book_before bitfinex.transient_raw_book_events[], p_order_book_after bitfinex.transient_raw_book_events[]) RETURNS bitfinex.transient_raw_book_events[]
    LANGUAGE sql IMMUTABLE
    AS $$
	with ob_before as (
			select *
			from unnest(p_order_book_before) 
		),
		ob_after as (
			select *
			from unnest(p_order_book_after) 
		),
		ts as (
			select distinct episode_timestamp as ts, channel_id	
			from  ob_after
		),
		ob_diff as (
		select coalesce(a.exchange_timestamp, (select ts from ts)) as exchange_timestamp,
				order_id,
				coalesce(a.price, 0), 
				coalesce(a.amount, case when b.amount > 0 then 1 when b.amount < 0 then -1 end), 
				coalesce(a.pair_id, b.pair_id), 
				a.local_timestamp,											-- when the diff event is inferred by us, it will be null
				coalesce(a.channel_id, (select channel_id from ts)),	  -- we need to set properly channel_id for the inferred deletion events too. Otherwise capture_transient_raw..() will miss them
				coalesce(a.episode_timestamp, (select ts from ts)) as episode_timestamp,
				a.event_no as event_no,
				0::integer
		from ob_before b full join ob_after a using (order_id) 
		where  ( a.price is not null and b.price is not null and a.price <> b.price ) or	
				( a.amount is not null and b.amount is not null and a.amount <> b.amount ) or
				( a.price is null and b.price > 0 ) or		-- order has not existed in ob_before, so skip deletion (it has been already deleted)
				( a.price > 0 and b.price is null )		
	)
	select array_agg(ob_diff::bitfinex.transient_raw_book_events order by order_id)	-- order by order_id is for debugging only
	from ob_diff
	;
$$;


ALTER FUNCTION bitfinex._diff_order_books(p_order_book_before bitfinex.transient_raw_book_events[], p_order_book_after bitfinex.transient_raw_book_events[]) OWNER TO "ob-analytics";

--
-- Name: _level3_matchable_events(timestamp with time zone, timestamp with time zone, integer, integer); Type: FUNCTION; Schema: bitfinex; Owner: ob-analytics
--

CREATE FUNCTION bitfinex._level3_matchable_events(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_price_decimal_places integer DEFAULT NULL::integer) RETURNS TABLE(microtimestamp timestamp with time zone, order_id bigint, event_no integer, price numeric, fill numeric, side character)
    LANGUAGE sql STABLE
    AS $$
with buys_already_matched as (
	select microtimestamp, buy_order_id as order_id, buy_event_no as event_no, sum(amount) as already_matched
	from obanalytics.matches_bitfinex
	where pair_id = p_pair_id
	  and microtimestamp between p_start_time and p_end_time
	  and buy_order_id is not null 
	  and buy_event_no is not null
	group by 1, 2 ,3
),
sells_already_matched as (
	select microtimestamp, sell_order_id as order_id, sell_event_no as event_no, sum(amount) as already_matched
	from obanalytics.matches_bitfinex
	where pair_id = p_pair_id
	  and microtimestamp between p_start_time and p_end_time
	  and sell_order_id is not null 
	  and sell_event_no is not null
	group by 1, 2 ,3
)
select microtimestamp, order_id, event_no, case when p_price_decimal_places is null then price else trunc(price, p_price_decimal_places) end,
		case when next_microtimestamp = '-infinity' then coalesce(nullif(fill,0), amount) - coalesce(already_matched,0)
			  when next_microtimestamp > '-infinity' then coalesce(fill,0) - coalesce(already_matched,0)
	    end	as fill, 
		side
from obanalytics.level3_bitfinex left join buys_already_matched using (microtimestamp, order_id, event_no)
where pair_id = p_pair_id
  and microtimestamp between p_start_time and p_end_time
  and side = 'b'																			  
union all
select microtimestamp, order_id, event_no, case when p_price_decimal_places is null then price else trunc(price, p_price_decimal_places) end,
		case when next_microtimestamp = '-infinity' then coalesce(nullif(fill,0), amount) - coalesce(already_matched,0)
			  when next_microtimestamp > '-infinity' then coalesce(fill,0) - coalesce(already_matched,0)
	    end	as fill, 
		side
from obanalytics.level3_bitfinex left join sells_already_matched using (microtimestamp, order_id, event_no)
where pair_id = p_pair_id
  and side = 's'																			  
  and microtimestamp between p_start_time and p_end_time;

$$;


ALTER FUNCTION bitfinex._level3_matchable_events(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_price_decimal_places integer) OWNER TO "ob-analytics";

--
-- Name: _matches_matchable_sets(timestamp with time zone, timestamp with time zone, smallint, interval, integer, integer, integer); Type: FUNCTION; Schema: bitfinex; Owner: ob-analytics
--

CREATE FUNCTION bitfinex._matches_matchable_sets(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id smallint, p_max_delay interval DEFAULT '00:00:01'::interval, p_max_group_size integer DEFAULT 3, p_max_set_size integer DEFAULT 10, p_price_decimal_places integer DEFAULT NULL::integer) RETURNS TABLE(group_size integer, set_id integer, trade_microtimestamp timestamp with time zone, fill numeric, price numeric, side character, origination character, ctids bitfinex._tableoid_ctid[])
    LANGUAGE sql STABLE
    AS $$

with recursive matches_set_starts as (
	select tableoid, ctid, 
		(buy_order_id is null and sell_order_id is null 
		 and ( (lag(buy_order_id) over w is not null or lag(sell_order_id) over w is not null ) 
			    or (lag(side) over w <> side)
			 	or (lag(price) over w <> price)
			 )
		)::integer as set_start, * 
	from obanalytics.matches_bitfinex
	where pair_id = p_pair_id
	  and microtimestamp between p_start_time and p_end_time																	  
	window w as (order by microtimestamp)
),
matches_sets as (
	select *, count(*) over (partition by set_id) as set_size
	from (
		select sum(set_start)  over (order by microtimestamp) as set_id, *
		from matches_set_starts
		where buy_order_id is null and sell_order_id is null
	) m
),
matches_by_groups as (
	select 1::integer as group_size, set_id, microtimestamp as trade_microtimestamp, amount as fill, price, side as origination, array_append('{}'::bitfinex._tableoid_ctid[], row(tableoid,ctid)::bitfinex._tableoid_ctid) as ctids
	from matches_sets
	where set_size <= p_max_set_size
	union all
	select group_size+1, matches_sets.set_id, matches_sets.microtimestamp, matches_sets.amount + fill, matches_sets.price, matches_sets.side,  array_append(ctids, row(tableoid,ctid)::bitfinex._tableoid_ctid)
	from matches_by_groups join matches_sets on matches_sets.microtimestamp > trade_microtimestamp 
								     and matches_sets.set_size <= p_max_set_size
									 and matches_by_groups.set_id = matches_sets.set_id
									 and matches_by_groups.price = matches_sets.price
									 and matches_by_groups.origination = matches_sets.side
	where matches_by_groups.group_size < p_max_group_size
),
matches_by_sets as (
	select matches_sets.set_size as group_size, matches_sets.set_id, matches_sets.microtimestamp as trade_microtimestamp, sum(amount) as fill, matches_sets.price, matches_sets.side as origination, 
	array_agg(row(tableoid,ctid)::bitfinex._tableoid_ctid) as ctids
	from matches_sets
	where set_size > p_max_group_size
	group by 1, 2, 3, 5, 6
), 
matches as (
	select group_size, set_id, trade_microtimestamp, fill, case when p_price_decimal_places is null then price else trunc(price, p_price_decimal_places) end as price, origination, ctids
	from matches_by_groups
	union all
	select group_size, set_id, trade_microtimestamp, fill, case when p_price_decimal_places is null then price else trunc(price, p_price_decimal_places) end as price, origination, ctids 
	from matches_by_sets
)
select group_size::integer, set_id::integer, trade_microtimestamp, fill, price, case origination when 'b' then 's' when 's' then 'b' end as side,  origination, ctids
from matches
where group_size > 1;

																																	 
$$;


ALTER FUNCTION bitfinex._matches_matchable_sets(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id smallint, p_max_delay interval, p_max_group_size integer, p_max_set_size integer, p_price_decimal_places integer) OWNER TO "ob-analytics";

--
-- Name: _update_order_book(bitfinex.transient_raw_book_events[], bitfinex.transient_raw_book_events[]); Type: FUNCTION; Schema: bitfinex; Owner: ob-analytics
--

CREATE FUNCTION bitfinex._update_order_book(p_order_book bitfinex.transient_raw_book_events[], p_update bitfinex.transient_raw_book_events[]) RETURNS bitfinex.transient_raw_book_events[]
    LANGUAGE sql STABLE
    AS $$
	with ob as (
			select *
			from unnest(p_order_book)
			where price > 0
		), 
		u as (
			select *
			from unnest(p_update)
		),
		order_book as (
		select coalesce(u.exchange_timestamp, ob.exchange_timestamp) as exchange_timestamp,
				order_id,
				coalesce(u.price, ob.price) as price,
				coalesce(u.amount, ob.amount) as amount,
				coalesce(u.pair_id, ob.pair_id) as pair_id,
				coalesce(u.local_timestamp, ob.local_timestamp) as local_timestamp,
				coalesce(u.channel_id, ob.channel_id) as channel_id,
				coalesce(u.episode_timestamp, (select distinct episode_timestamp from u )),
				u.event_no	-- not null only for an update produced from level3 to ensure continuity of event_no's
		from  ob full join  u using (order_id)
	)
	select array_agg(order_book::bitfinex.transient_raw_book_events)
	from order_book
	;
$$;


ALTER FUNCTION bitfinex._update_order_book(p_order_book bitfinex.transient_raw_book_events[], p_update bitfinex.transient_raw_book_events[]) OWNER TO "ob-analytics";

--
-- Name: capture_transient_raw_book_events(timestamp with time zone, timestamp with time zone, text, interval); Type: FUNCTION; Schema: bitfinex; Owner: ob-analytics
--

CREATE FUNCTION bitfinex.capture_transient_raw_book_events(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text, p_new_era_start_threshold interval DEFAULT '00:00:02'::interval) RETURNS SETOF obanalytics.level3
    LANGUAGE plpgsql
    SET work_mem TO '1GB'
    AS $$
declare
	p record;
	v_pair_id smallint;
	v_exchange_id smallint;
	v_price_precision smallint;
	v_fmu smallint;
	v_last_order_book record; -- obanalytics.level3_order_book_record[];
	v_open_orders bitfinex.transient_raw_book_events[];	
	v_era timestamptz;
begin
	select pair_id, fmu into strict v_pair_id, v_fmu
	from obanalytics.pairs
	where pair = upper(p_pair);
	
	select exchange_id into strict v_exchange_id
	from obanalytics.exchanges
	where exchange = 'bitfinex';
	
	select price_precision into strict v_price_precision
	from bitfinex.latest_symbol_details 
	where pair_id = v_pair_id;

	for p in with channels as (
						select channel_id, episode_timestamp as start_time, 
								coalesce(lead(episode_timestamp) over(partition by pair_id order by episode_timestamp) - '00:00:00.000001'::interval, 
										 'infinity') as end_time
						from bitfinex.transient_raw_book_channels 
						where pair_id = v_pair_id
				)
				select channel_id,
						greatest(start_time, p_start_time) as start_time, 
						least(end_time, p_end_time) as end_time,
						start_time between p_start_time and p_end_time as is_channel_starts
				from channels
				where start_time <= p_end_time
				  and end_time >= p_start_time
				order by 2	-- i.e. output's start_time
				loop
		select ts, ob into v_last_order_book
		from obanalytics.order_book(p.start_time, 
										   v_pair_id, v_exchange_id,
										   p_only_makers := false,	-- since exchanges sometimes output crossed order books, we'll consider ALL active orders
										   p_before := true);	

		select array_agg(row(microtimestamp, order_id, price,
				case side when 's' then -amount when 'b' then amount end,
				pair_id, null::timestamptz,-1, microtimestamp ,event_no,null::integer)::bitfinex.transient_raw_book_events) 
				into v_open_orders
		from unnest(v_last_order_book.ob);
		if p.is_channel_starts then	
			if (v_last_order_book is null or p.start_time - v_last_order_book.ts > p_new_era_start_threshold ) or
				(extract(month from v_last_order_book.ts) <> extract(month from p.start_time)) then	-- going over a partition boundary so need to start new era
																											 -- next_microtimestamp and price_microtimestamp can't refer beyond partition
				raise log 'Start new era for channel % interval % between % and %, threshold %', p.channel_id,  p.start_time -  v_last_order_book.ts, v_last_order_book.ts, p.start_time,  p_new_era_start_threshold;
				insert into obanalytics.level3_eras (era, pair_id, exchange_id)
				values (p.start_time, v_pair_id, v_exchange_id);
				
				v_open_orders := null;	-- event_no will start from scratch
			else
				raise log 'Continue previous era for new channel %, interval % between % and % ,threshold %', p.channel_id,  p.start_time -  v_last_order_book.ts, p.start_time,  v_last_order_book.ts, p_new_era_start_threshold;
				with to_be_replaced as (
					delete from bitfinex.transient_raw_book_events
					where pair_id = v_pair_id
					  and channel_id = p.channel_id
					  and episode_timestamp = p.start_time
					returning *
				),
				base_events as (
					select exchange_timestamp, order_id, round( price, v_price_precision) as price,
						round(amount, v_fmu) as amount, pair_id, local_timestamp, channel_id, episode_timestamp, event_no, bl
					from to_be_replaced 
					order by episode_timestamp, order_id, channel_id, pair_id, exchange_timestamp desc, local_timestamp desc
				)
				insert into bitfinex.transient_raw_book_events
				select (d).* 
				from unnest(bitfinex._diff_order_books(v_open_orders, array(select base_events::bitfinex.transient_raw_book_events
																					  	from base_events))) d
				;
			end if;
		else
			raise debug 'Continue previous era for old channel %', p.channel_id;
		end if;
		raise debug 'Starting processing of pair_id %, channel_id % from % till %', v_pair_id, p.channel_id, p.start_time, p.end_time;
		return query 
			with deleted_transient_events as (
				delete from bitfinex.transient_raw_book_events
				where pair_id = v_pair_id
				  and channel_id = p.channel_id
				  and episode_timestamp between p.start_time and p.end_time
				returning *
			),
			base_events as (
				-- takes only the latest event for given order_id within episode. If it is the lonely deletion, level3_incorporate_new_event() will simply drop it
				select distinct on (episode_timestamp, order_id, channel_id, pair_id ) exchange_timestamp, order_id, price, amount,
						pair_id, local_timestamp, channel_id, episode_timestamp, event_no, bl
				from (
					select exchange_timestamp, order_id, round( price, v_price_precision) as price,
						round(amount, v_fmu) as amount, pair_id, local_timestamp, channel_id, episode_timestamp, event_no, bl
					from deleted_transient_events 
				) a
				order by episode_timestamp, order_id, channel_id, pair_id, exchange_timestamp desc, local_timestamp desc
			),
			base_for_insert_level3 as (
				select *
				from base_events
				union all	-- will be empty if the new era starts
				select *
				from unnest(v_open_orders)	
				),
			for_insert_level3 as (
				select episode_timestamp as microtimestamp,
						order_id,
						(coalesce(first_value(event_no) over oe, 1) - 1)::integer + (row_number() over oe)::integer as event_no,
						side,
						case when price = 0 then abs(lag(price) over oe) else abs(price) end as  price, 
						case when price = 0 then abs(lag(amount) over oe) else abs(amount) end as amount,
						case when price = 0 then null else abs(lag(amount) over oe) - abs(amount) end as fill, 
						case when price > 0 then coalesce(lead(episode_timestamp) over oe, 'infinity'::timestamptz) when price = 0 then '-infinity'::timestamptz end  as next_microtimestamp,
						case when price > 0 then (coalesce(first_value(event_no) over oe, 1) )::integer + (row_number() over oe)::integer end as next_event_no,
						pair_id,
						local_timestamp,
						reincarnation_no,
						coalesce((price <> lag(price) over oe and price > 0 )::integer, 1) as is_price_changed,
						channel_id
				from (
					select *, sum(is_resurrected::integer) over o as reincarnation_no,
							 -- BITFINEX sometimes changes order type (!). We consider it to be a bug and will infer the order type from  the first known event for the order_id.
					         case when first_value(amount) over o < 0 then 's' when first_value(amount) over o > 0 then 'b' end as side
					from (
						select *, coalesce(lag(price) over o = 0, false) as is_resurrected
						from base_for_insert_level3
						where episode_timestamp <= p_end_time	
						window o as (partition by order_id order by exchange_timestamp, local_timestamp)
					) a
					window o as (partition by order_id order by exchange_timestamp, local_timestamp)
				) a
				window oe as (partition by order_id, reincarnation_no order by exchange_timestamp, local_timestamp)
			)		
			insert into obanalytics.level3 (exchange_id, microtimestamp, order_id, event_no, side, price, amount, fill, next_microtimestamp, next_event_no, 
											  pair_id, local_timestamp, price_microtimestamp, price_event_no, exchange_microtimestamp )
			select 1::smallint, -- exchange_id of bitfinex - see obanalytics.exchanges
					microtimestamp, order_id, 
					case when first_value(event_no) over o  > 1 and event_no = first_value(event_no) over o  and microtimestamp = first_value(microtimestamp) over o  then null 
						else event_no end as event_no,	-- event_no MUST be set by BEFORE trigger in order to update the previous event 
					side::character(1), price, amount, 
					case when first_value(event_no) over o  > 1 and event_no = first_value(event_no) over o  and microtimestamp = first_value(microtimestamp) over o  then null 							
						else fill end as fill,											-- see the comment for event_no
					next_microtimestamp,
					case when next_microtimestamp = 'infinity' then null else next_event_no end,
					pair_id, 
					-- null::smallint as exchange_id, 
					local_timestamp,
					case when first_value(event_no) over o  > 1 and event_no = first_value(event_no) over o  and microtimestamp = first_value(microtimestamp) over o  then null 							
						else price_microtimestamp end as price_microtimestamp,			-- see comment for event_no
					case when first_value(event_no) over o  > 1 and event_no = first_value(event_no) over o  and microtimestamp = first_value(microtimestamp) over o  then null 							
						else price_event_no end as price_event_no,						-- see comment for event_no
					null::timestamptz
			from (
				select *,
						-- checks that it is not a deletion event, when determining price_microtimestamp & price_event_no
						case when first_value(price)  over op > 0 then 
								first_value(microtimestamp)  over op
							  else 
								null	
						end as price_microtimestamp,	
						case when first_value(price) over op > 0 then 
								first_value(event_no) over op
							  else 
								null	
						end as price_event_no
				from (
					select *, sum(is_price_changed) over (partition by order_id, reincarnation_no order by microtimestamp) as price_group 			-- within an reincarnation of order_id
					from  for_insert_level3
					where price is not null -- when crossing a month boundary there can be deleted event with created in previous month. The record will have null price 
				) a						
				window op as (partition by order_id, reincarnation_no, price_group order by microtimestamp, event_no)
			) a
			where channel_id is distinct from -1 -- i.e. skip channel_id = -1 which represents open orders from level3 table					
			window o as (partition by order_id order by microtimestamp, event_no )   -- if the very first event_no for an order_id in this insert is not 1 then 
			order by microtimestamp, event_no nulls first  							  -- we will set event_no, fill, price_microtimestamp and price event_no to null
			returning *																	-- so level3_incorporate_new_event() will set these fields AND UPDATE PREVIOUS EVENT
			;																			-- nulls first in order by is important! 
	end loop;				
	return;
end;
$$;


ALTER FUNCTION bitfinex.capture_transient_raw_book_events(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair text, p_new_era_start_threshold interval) OWNER TO "ob-analytics";

--
-- Name: capture_transient_trades(timestamp with time zone, text); Type: FUNCTION; Schema: bitfinex; Owner: ob-analytics
--

CREATE FUNCTION bitfinex.capture_transient_trades(p_end_time timestamp with time zone, p_pair text DEFAULT 'BTCUSD'::text) RETURNS SETOF obanalytics.matches
    LANGUAGE sql
    AS $$
with deleted as (
	delete from bitfinex.transient_trades
	where transient_trades.pair_id = (select pair_id from obanalytics.pairs where pair = upper(p_pair))
	  and exchange_timestamp <= p_end_time
	returning transient_trades.*
)
insert into obanalytics.matches_bitfinex (amount, price, side, microtimestamp, local_timestamp, pair_id, exchange_trade_id)
select distinct on (exchange_timestamp, id) round(abs(qty), fmu), round(price, price_precision),  case when qty <0 then 's' else 'b' end, exchange_timestamp, local_timestamp, pair_id, id
from deleted join bitfinex.latest_symbol_details using (pair_id) join obanalytics.pairs using (pair_id)
order by exchange_timestamp, id
returning matches_bitfinex.*;

$$;


ALTER FUNCTION bitfinex.capture_transient_trades(p_end_time timestamp with time zone, p_pair text) OWNER TO "ob-analytics";

--
-- Name: match_price_and_fill_exact(timestamp with time zone, timestamp with time zone, integer, interval, integer); Type: FUNCTION; Schema: bitfinex; Owner: ob-analytics
--

CREATE FUNCTION bitfinex.match_price_and_fill_exact(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_max_delay interval DEFAULT '00:00:01'::interval, p_price_decimal_places integer DEFAULT NULL::integer) RETURNS SETOF obanalytics.matches
    LANGUAGE sql
    AS $$

with matches as (
	select tableoid, ctid, exchange_trade_id, case when p_price_decimal_places is null then price else trunc(price, p_price_decimal_places) end as price,
			amount as fill, microtimestamp as trade_microtimestamp, side as origination
	from obanalytics.matches_bitfinex
	where pair_id = p_pair_id
	  and microtimestamp between p_start_time and p_end_time
	  and buy_order_id is null and sell_order_id is null
),
joined as (
	select * , row_number() over (partition by exchange_trade_id order by microtimestamp ) as r,
				row_number() over (partition by order_id, event_no order by trade_microtimestamp ) as r_l3
	from bitfinex._level3_matchable_events(p_start_time, p_end_time, p_pair_id, p_price_decimal_places) 
		  join matches using (price, fill)
	where microtimestamp between trade_microtimestamp  and trade_microtimestamp + p_max_delay
	  and side <> origination
),
for_update as (
	select tableoid, ctid, microtimestamp, order_id, event_no, side
	from joined 
	where r  = 1 and r_l3 = 1
),
updated_matches as (
	update obanalytics.matches_bitfinex
	set buy_order_id = case when for_update.side = 'b' then order_id else buy_order_id end,
		buy_event_no = case when for_update.side = 'b' then event_no else buy_order_id end,
		sell_order_id = case when for_update.side = 's' then order_id else sell_order_id end,
		sell_event_no = case when for_update.side = 's' then event_no else sell_event_no end,
		microtimestamp = for_update.microtimestamp
	from for_update
	where matches_bitfinex.pair_id = p_pair_id
	  and for_update.ctid = matches_bitfinex.ctid
	  and for_update.tableoid = matches_bitfinex.tableoid
	returning matches_bitfinex.*
),
updated_buys as (
	update obanalytics.level3_bitfinex
	set amount = level3_bitfinex.amount - updated_matches.amount,
		fill = updated_matches.amount
	from updated_matches
	where updated_matches.buy_order_id is not null 
	  and level3_bitfinex.microtimestamp = updated_matches.microtimestamp
	  and level3_bitfinex.order_id = buy_order_id 
	  and level3_bitfinex.event_no = buy_event_no
	  and level3_bitfinex.pair_id = p_pair_id
	  and level3_bitfinex.side = 'b'
	  and fill is null
),
updated_sells as (
	update obanalytics.level3_bitfinex
	set amount = level3_bitfinex.amount - updated_matches.amount,
		fill = updated_matches.amount
	from updated_matches
	where updated_matches.sell_order_id is not null 
	  and level3_bitfinex.microtimestamp = updated_matches.microtimestamp
	  and level3_bitfinex.order_id = sell_order_id 
	  and level3_bitfinex.event_no = sell_event_no
	  and level3_bitfinex.pair_id = p_pair_id
	  and level3_bitfinex.side = 's'	
	  and fill is null
)
select *
from updated_matches;

$$;


ALTER FUNCTION bitfinex.match_price_and_fill_exact(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_max_delay interval, p_price_decimal_places integer) OWNER TO "ob-analytics";

--
-- Name: match_price_and_sum_of_fill_exact(timestamp with time zone, timestamp with time zone, smallint, interval, integer, integer, integer); Type: FUNCTION; Schema: bitfinex; Owner: ob-analytics
--

CREATE FUNCTION bitfinex.match_price_and_sum_of_fill_exact(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id smallint, p_max_delay interval DEFAULT '00:00:01'::interval, p_max_group_size integer DEFAULT 3, p_max_set_size integer DEFAULT 10, p_price_decimal_places integer DEFAULT NULL::integer) RETURNS SETOF obanalytics.matches
    LANGUAGE sql
    AS $$

with for_update_base as (
	select distinct on (microtimestamp, order_id, event_no) *
	from bitfinex._level3_matchable_events(p_start_time, p_end_time, p_pair_id ) 
		  join bitfinex._matches_matchable_sets(p_start_time, p_end_time, p_pair_id, p_max_delay, p_max_group_size, p_max_set_size, p_price_decimal_places) a using (price, fill, side)
	where microtimestamp between trade_microtimestamp  and trade_microtimestamp + p_max_delay
	order by microtimestamp, order_id, event_no, trade_microtimestamp
),
-- we need to ensure that each match (i.e. trade) belongs to a single group only
for_update as (
	select l.*
	from for_update_base l left join for_update_base r on l.ctids && r.ctids  and not (l.microtimestamp = r.microtimestamp and l.order_id = r.order_id and l.event_no = r.event_no)
	where r.microtimestamp is null 
	   or l.microtimestamp < r.microtimestamp 
	   or ( l.microtimestamp = r.microtimestamp and l.trade_microtimestamp < r.trade_microtimestamp )
	   or ( l.microtimestamp = r.microtimestamp and l.trade_microtimestamp = r.trade_microtimestamp and l.ctids < r.ctids)	-- choose one of them (arbitrarily)
),
updated_matches as (
	update obanalytics.matches_bitfinex
	set buy_order_id = case when for_update.side = 'b' then order_id else buy_order_id end,
		buy_event_no = case when for_update.side = 'b' then event_no else buy_event_no end,
		sell_order_id = case when for_update.side = 's' then order_id else sell_order_id end,
		sell_event_no = case when for_update.side = 's' then event_no else sell_event_no end,
		microtimestamp = for_update.microtimestamp
	from for_update join unnest(ctids) pks on true
	where matches_bitfinex.pair_id = p_pair_id
	  and matches_bitfinex.ctid = pks.ctid 
	  and matches_bitfinex.tableoid = pks.tableoid
	returning matches_bitfinex.*
),
updated_buys as (
	update obanalytics.level3_bitfinex
	set amount = level3_bitfinex.amount - updated_matches.amount,
		fill = updated_matches.amount
	from ( select microtimestamp, buy_order_id, buy_event_no, sum(amount) as amount
			from updated_matches
			where updated_matches.buy_order_id is not null 
			group by 1,2,3
		 ) updated_matches
	where level3_bitfinex.microtimestamp = updated_matches.microtimestamp
	  and level3_bitfinex.order_id = buy_order_id 
	  and level3_bitfinex.event_no = buy_event_no
	  and level3_bitfinex.pair_id = p_pair_id
	  and level3_bitfinex.side = 'b'
	  and fill is null
),
updated_sells as (
	update obanalytics.level3_bitfinex
	set amount = level3_bitfinex.amount - updated_matches.amount,
		fill = updated_matches.amount
	from ( select microtimestamp, sell_order_id, sell_event_no, sum(amount) as amount
			from updated_matches
			where updated_matches.sell_order_id is not null 
			group by 1,2,3
		 ) updated_matches
	where level3_bitfinex.microtimestamp = updated_matches.microtimestamp
	  and level3_bitfinex.order_id = sell_order_id 
	  and level3_bitfinex.event_no = sell_event_no
	  and level3_bitfinex.pair_id = p_pair_id
	  and level3_bitfinex.side = 's'	
	  and fill is null
)
select *
from updated_matches;

																																	 
$$;


ALTER FUNCTION bitfinex.match_price_and_sum_of_fill_exact(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id smallint, p_max_delay interval, p_max_group_size integer, p_max_set_size integer, p_price_decimal_places integer) OWNER TO "ob-analytics";

--
-- Name: pga_capture_transient(text, interval, interval); Type: FUNCTION; Schema: bitfinex; Owner: ob-analytics
--

CREATE FUNCTION bitfinex.pga_capture_transient(p_pair text, p_delay interval DEFAULT '00:02:00'::interval, p_max_interval interval DEFAULT '04:00:00'::interval) RETURNS integer
    LANGUAGE plpgsql
    AS $$declare
	v_events_start timestamptz;
	v_events_end timestamptz;
	v_trades_end timestamptz;
	
	v_last_event timestamptz;
	v_last_era timestamptz;
	v_pair_id smallint;
	v_exchange_id smallint;
	v_channel_id integer;
	
begin 

	select pair_id into strict v_pair_id
	from obanalytics.pairs where pair = upper(p_pair);
	
	select exchange_id into strict v_exchange_id
	from obanalytics.exchanges where exchange = 'bitfinex';
 
	select max(exchange_timestamp)  - p_delay into v_trades_end
	from bitfinex.transient_trades 
	where pair_id = v_pair_id;
																			  
	perform bitfinex.capture_transient_trades(v_trades_end,  p_pair);
	
	select min(episode_timestamp), max(episode_timestamp) - p_delay into v_events_start, v_events_end
	from bitfinex.transient_raw_book_events 
	where pair_id = v_pair_id;
																		 
	if extract (month from v_events_start) <> extract (month from v_events_end) then 
		v_events_end = date_trunc('month', v_events_end) - '00:00:00.000001'::interval;
		raise debug 'updated v_events_end to %', v_events_end;
	else
	
		select max(era) into strict v_last_era 
		from obanalytics.level3_eras
		where pair_id = v_pair_id
		  and exchange_id = v_exchange_id;
		  
		select max(microtimestamp) into strict v_last_event
		from obanalytics.level3_bitfinex
		where pair_id = v_pair_id
		  and microtimestamp >= v_last_era;	-- to avoid search over ALL partitions of level3 - the query optimizer is not smart enough yet unfortunately
																				  
		if extract(month from v_last_event) <> extract(month from v_events_start) then
		
			v_events_start := date_trunc('month', v_events_start);
			
			raise debug 'updated v_events_start to %', v_events_start;
		
			select channel_id into strict v_channel_id
			from bitfinex.transient_raw_book_events
			where pair_id = v_pair_id
			order by episode_timestamp
			limit 1;
			
			
			insert into bitfinex.transient_raw_book_channels (episode_timestamp, pair_id, channel_id)
			values (v_events_start, v_pair_id, v_channel_id);
			
			insert into bitfinex.transient_raw_book_events (exchange_timestamp, order_id, price, amount, pair_id, local_timestamp,
															  channel_id, episode_timestamp, event_no, bl)
			select v_events_start, order_id, price,
					case side when 's' then -amount when 'b' then amount end, pair_id, null::timestamptz,
					v_channel_id, v_events_start,null, null::integer
			from obanalytics.order_book(v_events_start, v_pair_id, v_exchange_id,
										   p_only_makers := false,	-- since exchanges sometimes output crossed order books, we'll consider ALL active orders
										   p_before := true) join unnest(ob) on true;
										   
			raise debug 'Created snapshot for channel_id % at %', v_channel_id, v_events_start;
		end if;
		-- perform bitfinex.capture_transient_raw_book_events(v_events_start, v_events_end, p_pair);
	end if;
	
	if v_events_start + p_max_interval < v_events_end then
		v_events_end := v_events_start + p_max_interval;
		raise debug 'updated v_events_end to % (p_max_interval is exceeded)', v_events_end;
	end if;	
	perform bitfinex.capture_transient_raw_book_events(v_events_start, v_events_end, p_pair);
	-- perform obanalytics.fix_crossed_books(v_events_start, v_events_end, v_pair_id, v_exchange_id);
	return 0;
end;
$$;


ALTER FUNCTION bitfinex.pga_capture_transient(p_pair text, p_delay interval, p_max_interval interval) OWNER TO "ob-analytics";

--
-- Name: pga_match(text, interval, interval, timestamp with time zone); Type: FUNCTION; Schema: bitfinex; Owner: ob-analytics
--

CREATE FUNCTION bitfinex.pga_match(p_pair text, p_delay interval DEFAULT '00:02:00'::interval, p_max_interval interval DEFAULT '02:00:00'::interval, p_ts_within_era timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS TABLE(o_start timestamp with time zone, o_end timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
declare
	v_pair_id smallint;
	v_frame_start timestamptz;	
	v_frame_end timestamptz;
	v_price_precision integer;
	v_max_price_precision integer;
begin 
	
	select pair_id into strict v_pair_id
	from obanalytics.pairs
	where pair = upper(p_pair);
	
	select price_precision into v_max_price_precision
	from bitfinex.latest_symbol_details
	where pair_id = v_pair_id;
	
	if p_ts_within_era is null then 
	
		select max(era) into strict v_frame_start
		from obanalytics.level3_eras_bitfinex
		where pair_id = v_pair_id
		  and era <= now() - p_max_interval;
		
		v_frame_end := 'infinity';
	else
	
		select era,  era_end into v_frame_start, v_frame_end
		from (
			select era, coalesce( lead(era) over (order by era) - '00:00:00.000001'::interval, 'infinity') as era_end
			from obanalytics.level3_eras_bitfinex
			where pair_id = v_pair_id
		) a
		where p_ts_within_era between era and era_end;
		
	end if;

	select max(microtimestamp) into o_start
	from obanalytics.matches_bitfinex 
	where pair_id = v_pair_id
	  and microtimestamp between v_frame_start and v_frame_end
	  and (buy_order_id is not null or sell_order_id is not null);
	  
	if o_start is not null then 
		select coalesce(max(microtimestamp) - p_delay, 'infinity'::timestamptz) into o_end
		from obanalytics.matches_bitfinex
		where pair_id = v_pair_id
		  and microtimestamp between v_frame_start and v_frame_end;
		
	else
		select min(microtimestamp) , least(v_frame_end, min(microtimestamp) + p_max_interval) into o_start, o_end
		from obanalytics.matches_bitfinex 
		where pair_id = v_pair_id
		  and microtimestamp between v_frame_start and v_frame_end;
		
	end if;	
	
	if o_start + p_max_interval < o_end then
		o_end := o_start + p_max_interval;
	end if;
	
	raise debug 'o_start: %, o_end: %', o_start, o_end;
	
	v_price_precision := v_max_price_precision;
	loop
		perform bitfinex.match_price_and_fill_exact(o_start, o_end, v_pair_id, p_price_decimal_places := v_price_precision);
		if not found then 
			if v_max_price_precision - v_price_precision > 1 then 
				exit;
			else
				v_price_precision := v_price_precision - 1;
			end if;
		end if;
	end loop;		
	v_price_precision := v_max_price_precision;
	loop
		perform bitfinex.match_price_and_sum_of_fill_exact(o_start, o_end, v_pair_id, p_price_decimal_places := v_price_precision);
		if not found then 
			if v_max_price_precision - v_price_precision > 1 then 
				exit;
			else
				v_price_precision := v_price_precision - 1;
			end if;
		end if;
	end loop;		
	

	return next;
end;
$$;


ALTER FUNCTION bitfinex.pga_match(p_pair text, p_delay interval, p_max_interval interval, p_ts_within_era timestamp with time zone) OWNER TO "ob-analytics";

--
-- Name: update_symbol_details(text, smallint, numeric, numeric, numeric, numeric, text, boolean); Type: FUNCTION; Schema: bitfinex; Owner: ob-analytics
--

CREATE FUNCTION bitfinex.update_symbol_details(p_pair text, p_price_precision smallint, p_initial_margin numeric, p_minimum_margin numeric, p_maximum_order_size numeric, p_minimum_order_size numeric, p_expiration text, p_margin boolean) RETURNS boolean
    LANGUAGE plpgsql
    AS $$

declare
	v_pair_id smallint;
begin

	select pair_id into v_pair_id
	from obanalytics.pairs
	where pair = upper(p_pair);
	
	if v_pair_id is not null then
		if exists (select 1 from bitfinex.symbol_details where pair_id = v_pair_id ) then 
			insert into bitfinex.symbol_details (pair_id, price_precision, initial_margin,minimum_margin,maximum_order_size,minimum_order_size,expiration,margin,known_since)					
			select v_pair_id, p_price_precision, p_initial_margin,p_minimum_margin,p_maximum_order_size,p_minimum_order_size,p_expiration,p_margin,current_timestamp
			from bitfinex.symbol_details
			 where pair_id = v_pair_id and 
			 known_since = (select max(known_since) from bitfinex.symbol_details where pair_id = v_pair_id ) and
			 (	price_precision <> p_price_precision or
				initial_margin <> p_initial_margin or
				minimum_margin <> p_minimum_margin or
				maximum_order_size <> p_maximum_order_size or
				minimum_order_size <> p_minimum_order_size or
				expiration <> p_expiration or
				margin <> p_margin 
			 );
			 return found;
		else
			insert into bitfinex.symbol_details (pair_id, price_precision, initial_margin,minimum_margin,maximum_order_size,minimum_order_size,expiration,margin,known_since)					
			values(v_pair_id, p_price_precision, p_initial_margin,p_minimum_margin,p_maximum_order_size,p_minimum_order_size,p_expiration,p_margin,current_timestamp);
			return true;
		end if;
	else
		return false;
	end if;
end;
$$;


ALTER FUNCTION bitfinex.update_symbol_details(p_pair text, p_price_precision smallint, p_initial_margin numeric, p_minimum_margin numeric, p_maximum_order_size numeric, p_minimum_order_size numeric, p_expiration text, p_margin boolean) OWNER TO "ob-analytics";

--
-- Name: transient_raw_book_agg(bitfinex.transient_raw_book_events[]); Type: AGGREGATE; Schema: bitfinex; Owner: ob-analytics
--

CREATE AGGREGATE bitfinex.transient_raw_book_agg(bitfinex.transient_raw_book_events[]) (
    SFUNC = bitfinex._update_order_book,
    STYPE = bitfinex.transient_raw_book_events[]
);


ALTER AGGREGATE bitfinex.transient_raw_book_agg(bitfinex.transient_raw_book_events[]) OWNER TO "ob-analytics";

--
-- Name: symbol_details; Type: TABLE; Schema: bitfinex; Owner: ob-analytics
--

CREATE TABLE bitfinex.symbol_details (
    pair_id smallint NOT NULL,
    price_precision smallint NOT NULL,
    initial_margin numeric NOT NULL,
    minimum_margin numeric NOT NULL,
    maximum_order_size numeric NOT NULL,
    minimum_order_size numeric NOT NULL,
    expiration text NOT NULL,
    margin boolean NOT NULL,
    known_since timestamp with time zone NOT NULL
);


ALTER TABLE bitfinex.symbol_details OWNER TO "ob-analytics";

--
-- Name: latest_symbol_details; Type: VIEW; Schema: bitfinex; Owner: ob-analytics
--

CREATE VIEW bitfinex.latest_symbol_details AS
 SELECT DISTINCT ON (symbol_details.pair_id) symbol_details.pair_id,
    symbol_details.price_precision,
    symbol_details.initial_margin,
    symbol_details.minimum_margin,
    symbol_details.maximum_order_size,
    symbol_details.minimum_order_size,
    symbol_details.expiration,
    symbol_details.margin,
    symbol_details.known_since
   FROM bitfinex.symbol_details
  ORDER BY symbol_details.pair_id, symbol_details.known_since DESC;


ALTER TABLE bitfinex.latest_symbol_details OWNER TO "ob-analytics";

--
-- Name: transient_raw_book_channels; Type: TABLE; Schema: bitfinex; Owner: ob-analytics
--

CREATE TABLE bitfinex.transient_raw_book_channels (
    episode_timestamp timestamp with time zone NOT NULL,
    pair_id smallint NOT NULL,
    channel_id integer NOT NULL
);


ALTER TABLE bitfinex.transient_raw_book_channels OWNER TO "ob-analytics";

--
-- Name: transient_trades; Type: TABLE; Schema: bitfinex; Owner: ob-analytics
--

CREATE TABLE bitfinex.transient_trades (
    id bigint NOT NULL,
    qty numeric NOT NULL,
    price numeric NOT NULL,
    local_timestamp timestamp with time zone NOT NULL,
    exchange_timestamp timestamp with time zone NOT NULL,
    pair_id smallint NOT NULL,
    channel_id integer NOT NULL,
    trade_id bigint NOT NULL
);


ALTER TABLE bitfinex.transient_trades OWNER TO "ob-analytics";

--
-- Name: transient_trades_trade_id_seq; Type: SEQUENCE; Schema: bitfinex; Owner: ob-analytics
--

CREATE SEQUENCE bitfinex.transient_trades_trade_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE bitfinex.transient_trades_trade_id_seq OWNER TO "ob-analytics";

--
-- Name: transient_trades_trade_id_seq; Type: SEQUENCE OWNED BY; Schema: bitfinex; Owner: ob-analytics
--

ALTER SEQUENCE bitfinex.transient_trades_trade_id_seq OWNED BY bitfinex.transient_trades.trade_id;


--
-- Name: transient_trades trade_id; Type: DEFAULT; Schema: bitfinex; Owner: ob-analytics
--

ALTER TABLE ONLY bitfinex.transient_trades ALTER COLUMN trade_id SET DEFAULT nextval('bitfinex.transient_trades_trade_id_seq'::regclass);


--
-- Name: symbol_details symbol_details_pkey; Type: CONSTRAINT; Schema: bitfinex; Owner: ob-analytics
--

ALTER TABLE ONLY bitfinex.symbol_details
    ADD CONSTRAINT symbol_details_pkey PRIMARY KEY (pair_id, known_since);


--
-- Name: transient_raw_book_events_idx_channel; Type: INDEX; Schema: bitfinex; Owner: ob-analytics
--

CREATE INDEX transient_raw_book_events_idx_channel ON bitfinex.transient_raw_book_events USING btree (pair_id, channel_id, episode_timestamp);


--
-- PostgreSQL database dump complete
--

