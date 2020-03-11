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
-- Name: obanalytics; Type: SCHEMA; Schema: -; Owner: ob-analytics
--

CREATE SCHEMA obanalytics;


ALTER SCHEMA obanalytics OWNER TO "ob-analytics";

--
-- Name: level1; Type: TYPE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TYPE obanalytics.level1 AS (
	best_bid_price numeric,
	best_bid_qty numeric,
	best_ask_price numeric,
	best_ask_qty numeric,
	microtimestamp timestamp with time zone,
	pair_id smallint,
	exchange_id smallint
);


ALTER TYPE obanalytics.level1 OWNER TO "ob-analytics";

--
-- Name: level2; Type: TYPE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TYPE obanalytics.level2 AS (
	microtimestamp timestamp with time zone,
	pair_id smallint,
	exchange_id smallint,
	"precision" character(2),
	price numeric,
	volume numeric,
	side character(1),
	bps_level integer
);


ALTER TYPE obanalytics.level2 OWNER TO "ob-analytics";

--
-- Name: level2_depth_record; Type: TYPE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TYPE obanalytics.level2_depth_record AS (
	price numeric,
	volume numeric,
	side character(1),
	bps_level integer
);


ALTER TYPE obanalytics.level2_depth_record OWNER TO "ob-analytics";

--
-- Name: level2_depth_summary_internal_state; Type: TYPE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TYPE obanalytics.level2_depth_summary_internal_state AS (
	full_depth obanalytics.level2_depth_record[],
	bps_step integer,
	max_bps_level integer,
	pair_id smallint
);


ALTER TYPE obanalytics.level2_depth_summary_internal_state OWNER TO "ob-analytics";

--
-- Name: level2_depth_summary_record; Type: TYPE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TYPE obanalytics.level2_depth_summary_record AS (
	price numeric,
	volume numeric,
	side character(1),
	bps_level integer
);


ALTER TYPE obanalytics.level2_depth_summary_record OWNER TO "ob-analytics";

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: level3; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3 (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint NOT NULL,
    exchange_id smallint NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY LIST (exchange_id);


ALTER TABLE obanalytics.level3 OWNER TO "ob-analytics";

--
-- Name: COLUMN level3.exchange_microtimestamp; Type: COMMENT; Schema: obanalytics; Owner: ob-analytics
--

COMMENT ON COLUMN obanalytics.level3.exchange_microtimestamp IS 'An microtimestamp of an event as asigned by an exchange. Not null if different from ''microtimestamp''';


--
-- Name: pair_of_ob; Type: TYPE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TYPE obanalytics.pair_of_ob AS (
	ob1 obanalytics.level3[],
	ob2 obanalytics.level3[]
);


ALTER TYPE obanalytics.pair_of_ob OWNER TO "ob-analytics";

--
-- Name: matches; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches (
    amount numeric NOT NULL,
    price numeric NOT NULL,
    side character(1) NOT NULL,
    microtimestamp timestamp with time zone NOT NULL,
    buy_order_id bigint,
    buy_event_no integer,
    sell_order_id bigint,
    sell_event_no integer,
    buy_match_rule smallint,
    sell_match_rule smallint,
    local_timestamp timestamp with time zone,
    exchange_id smallint NOT NULL,
    pair_id smallint NOT NULL,
    exchange_side character(1),
    exchange_trade_id bigint,
    exchange_microtimestamp timestamp with time zone
)
PARTITION BY LIST (exchange_id);


ALTER TABLE obanalytics.matches OWNER TO "ob-analytics";

--
-- Name: COLUMN matches.exchange_side; Type: COMMENT; Schema: obanalytics; Owner: ob-analytics
--

COMMENT ON COLUMN obanalytics.matches.exchange_side IS 'Type of trade as reported by an exchange. Not null if different from ''trade_type''';


--
-- Name: _create_level2_partition(text, text, character, integer, integer, boolean); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics._create_level2_partition(p_exchange text, p_pair text, p_precision character, p_year integer, p_month integer, p_execute boolean DEFAULT true) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$

declare
	i integer;
	v_exchange_id smallint;
	v_pair_id smallint;
	v_from timestamptz;
	v_to timestamptz;
	
	v_parent_table text;
	
	v_table_name text;
	v_statement text;
	v_statements text[];
	V_SCHEMA constant text default 'obanalytics.';
begin 

	if not lower(p_precision) in ('r0', 'p0', 'p1', 'p2', 'p3', 'p4') then 
		raise exception 'Invalid p_precision: %. Valid values are r0, p0, p1, p2, p3, p4', p_precision;
	end if;
	v_from := make_timestamptz(p_year, p_month, 1, 0, 0, 0);	-- will use the current timezone 
	v_to := v_from + '1 month'::interval;
	
	select pair_id into strict v_pair_id
	from obanalytics.pairs
	where pair = upper(p_pair);
	
	select exchange_id into strict v_exchange_id
	from obanalytics.exchanges
	where exchange = lower(p_exchange);

	
	v_parent_table := 'level2';
	v_table_name := v_parent_table || '_' || p_exchange;

	i = 1;
	v_statements[i] := 'create table if not exists ' || V_SCHEMA || v_table_name || ' partition of '|| V_SCHEMA ||v_parent_table||
						' for values in ('|| v_exchange_id || ') partition by list ( pair_id )' ;

	i := i+1;
	v_statements[i] := 'alter table ' || V_SCHEMA || v_table_name || ' alter column exchange_id set default ' || v_exchange_id;

	v_parent_table := v_table_name;
	v_table_name := v_parent_table || '_' || lower(p_pair);
	
	i := i + 1;
	v_statements[i] := 'create table if not exists '||V_SCHEMA || v_table_name || ' partition of '|| V_SCHEMA ||v_parent_table||
						' for values in ('|| v_pair_id || ') partition by list (precision)';
	i := i+1;
	v_statements[i] := 'alter table ' || V_SCHEMA || v_table_name || ' alter column pair_id set default ' || v_pair_id;

	v_parent_table := v_table_name;
	v_table_name := v_parent_table || '_' || lower(p_precision);
	i := i + 1;
	v_statements[i] := 'create table if not exists '||V_SCHEMA || v_table_name || ' partition of '|| V_SCHEMA ||v_parent_table||
						' for values in ('|| quote_literal(p_precision) || ') partition by range (microtimestamp)';
	i := i+1;
	v_statements[i] := 'alter table ' || V_SCHEMA || v_table_name || ' alter column precision set default ' || quote_literal(p_precision);

	i := i+1;
	v_statements[i] := 'alter table ' || V_SCHEMA || v_table_name || ' alter column microtimestamp set statistics 1000 ';

	v_parent_table := v_table_name;
	-- We need a shorter name for the leafs - we are confined by max_identifier_length 
	v_table_name :=  'level2_' || lpad(v_exchange_id::text, 2,'0') || lpad(v_pair_id::text, 3,'0')|| p_precision || p_year || lpad(p_month::text, 2, '0') ;
	i := i + 1;
	
	v_statements[i] := 'create table if not exists '||V_SCHEMA ||v_table_name||' partition of '||V_SCHEMA ||v_parent_table||
							' for values from ('||quote_literal(v_from::timestamptz)||') to (' ||quote_literal(v_to::timestamptz) || ')';
							
	i := i+1;
	v_statements[i] := 'alter table ' || V_SCHEMA || v_table_name || ' alter column exchange_id set default ' || v_exchange_id;

	i := i+1;
	v_statements[i] := 'alter table ' || V_SCHEMA || v_table_name || ' alter column precision set default ' || quote_literal(p_precision);

	i := i+1;
	v_statements[i] := 'alter table ' || V_SCHEMA || v_table_name || ' alter column pair_id set default ' || v_pair_id;

	v_statement := 	'alter table '|| V_SCHEMA || v_table_name || ' add constraint '  || v_table_name ;
	
	i := i + 1;
	v_statements[i] := v_statement || '_pkey primary key (microtimestamp) ';  
	
	i := i+1;
	v_statements[i] := 'alter table '|| V_SCHEMA || v_table_name || ' set ( autovacuum_vacuum_scale_factor= 0.0 , autovacuum_vacuum_threshold = 10000)';
	
							
	foreach v_statement in array v_statements loop
		if p_execute then 
			raise log '%', v_statement;
			execute v_statement;
		else
			raise debug '%', v_statement;
		end if;		
	end loop;		
	return;
end;

$$;


ALTER FUNCTION obanalytics._create_level2_partition(p_exchange text, p_pair text, p_precision character, p_year integer, p_month integer, p_execute boolean) OWNER TO "ob-analytics";

--
-- Name: _create_level3_partition(text, character, text, integer, integer, boolean); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics._create_level3_partition(p_exchange text, p_side character, p_pair text, p_year integer, p_month integer, p_execute boolean DEFAULT true) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$declare
	i integer;
	v_exchange_id smallint;
	v_pair_id smallint;
	v_from timestamptz;
	v_to timestamptz;
	
	v_parent_table text;
	
	v_table_name text;
	v_statement text;
	v_statements text[];
	V_SCHEMA constant text default 'obanalytics.';
begin 

	if not lower(p_side) in ('b', 's') then 
		raise exception 'Invalid p_side: % ', p_side;
	end if;
	v_from := make_timestamptz(p_year, p_month, 1, 0, 0, 0);	-- will use the current timezone 
	v_to := v_from + '1 month'::interval;
	
	select pair_id into strict v_pair_id
	from obanalytics.pairs
	where pair = upper(p_pair);
	
	select exchange_id into strict v_exchange_id
	from obanalytics.exchanges
	where exchange = lower(p_exchange);

	
	v_parent_table := 'level3';
	v_table_name := v_parent_table || '_' || p_exchange;

	i = 1;
	v_statements[i] := 'create table if not exists ' || V_SCHEMA || v_table_name || ' partition of '|| V_SCHEMA ||v_parent_table||
						' for values in ('|| v_exchange_id || ') partition by list ( pair_id )' ;

	i := i+1;
	v_statements[i] := 'alter table ' || V_SCHEMA || v_table_name || ' alter column exchange_id set default ' || v_exchange_id;

	v_parent_table := v_table_name;
	v_table_name := v_parent_table || '_' || lower(p_pair);
	
	i := i + 1;
	v_statements[i] := 'create table if not exists '||V_SCHEMA || v_table_name || ' partition of '|| V_SCHEMA ||v_parent_table||
						' for values in ('|| v_pair_id || ') partition by list (side)';
	i := i+1;
	v_statements[i] := 'alter table ' || V_SCHEMA || v_table_name || ' alter column pair_id set default ' || v_pair_id;

	i := i+1;
	v_statements[i] := 'alter table ' || V_SCHEMA || v_table_name || ' alter column microtimestamp set statistics 1000 ';

	v_parent_table := v_table_name;
	v_table_name := v_parent_table || '_' || lower(p_side);
	i := i + 1;
	v_statements[i] := 'create table if not exists '||V_SCHEMA || v_table_name || ' partition of '|| V_SCHEMA ||v_parent_table||
						' for values in ('|| quote_literal(p_side) || ') partition by range (microtimestamp)';
	i := i+1;
	v_statements[i] := 'alter table ' || V_SCHEMA || v_table_name || ' alter column side set default ' || quote_literal(p_side);
	
	

	v_parent_table := v_table_name;
	-- We need a shorter name for the leafs - we are confined by max_identifier_length 
	v_table_name :=  'level3_' || lpad(v_exchange_id::text, 2,'0') || lpad(v_pair_id::text, 3,'0')|| p_side || p_year || lpad(p_month::text, 2, '0') ;
	i := i + 1;
	
	v_statements[i] := 'create table if not exists data.' ||v_table_name||' partition of '||V_SCHEMA ||v_parent_table||
							' for values from ('||quote_literal(v_from::timestamptz)||') to (' ||quote_literal(v_to::timestamptz) || ')';
							
	i := i+1;
	v_statements[i] := 'alter table data.' || v_table_name || ' alter column exchange_id set default ' || v_exchange_id;

	i := i+1;
	v_statements[i] := 'alter table data.' || v_table_name || ' alter column side set default ' || quote_literal(p_side);

	i := i+1;
	v_statements[i] := 'alter table data.' || v_table_name || ' alter column pair_id set default ' || v_pair_id;

	v_statement := 	'alter table data.' || v_table_name || ' add constraint '  || v_table_name ;
	
	i := i + 1;
	v_statements[i] := v_statement || '_pkey primary key (microtimestamp, order_id, event_no) ';  
	
	i := i + 1;
	v_statements[i] := v_statement || '_fkey_level3_next foreign key (next_microtimestamp, order_id, next_event_no) references data.'||v_table_name ||
							' match simple on update cascade on delete no action deferrable initially deferred';
	i := i + 1;
	v_statements[i] := v_statement || '_fkey_level3_price foreign key (price_microtimestamp, order_id, price_event_no) references data.'||v_table_name ||
							' match simple on update cascade on delete no action deferrable initially deferred';

	i := i+1;
	v_statements[i] := v_statement || '_unique_next unique (next_microtimestamp, order_id, next_event_no) deferrable initially deferred';
	
	i := i+1;
	v_statements[i] := 'alter table data.' || v_table_name || ' set ( autovacuum_vacuum_scale_factor= 0.0 , autovacuum_vacuum_threshold = 10000)';
	
	i := i+1;
	v_statements[i] := 'create trigger '||v_table_name||'_ba_incorporate_new_event before insert on data.'||v_table_name||
		' for each row execute procedure obanalytics.level3_incorporate_new_event()';

	i := i+1;
	v_statements[i] := 'create trigger '||v_table_name||'_bz_save_exchange_microtimestamp before update of microtimestamp on data.'||v_table_name||
		' for each row execute procedure obanalytics.save_exchange_microtimestamp()';
		
    i := i+1;
	v_statements[i] := 'create index '||v_table_name||'_fkey_level3_price on data.'|| v_table_name || '(price_microtimestamp, order_id, price_event_no)';

	
							
	foreach v_statement in array v_statements loop
		if p_execute then 
			raise log '%', v_statement;
			execute v_statement;
		else
			raise debug '%', v_statement;
		end if;		
	end loop;		
	return;
end;

$$;


ALTER FUNCTION obanalytics._create_level3_partition(p_exchange text, p_side character, p_pair text, p_year integer, p_month integer, p_execute boolean) OWNER TO "ob-analytics";

--
-- Name: _create_matches_partition(text, text, integer, integer, boolean); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics._create_matches_partition(p_exchange text, p_pair text, p_year integer, p_month integer, p_execute boolean DEFAULT true) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare
	i integer;
	v_exchange_id smallint;
	v_pair_id smallint;
	v_from timestamptz;
	v_to timestamptz;
	
	v_parent_table text;
	v_buy_orders_table text;
	v_sell_orders_table text;
	
	v_table_name text;
	v_statement text;
	v_statements text[];
	V_SCHEMA constant text default 'obanalytics.';
begin 

	v_from := make_timestamptz(p_year, p_month, 1, 0, 0, 0);	-- will use the current timezone 
	v_to := v_from + '1 month'::interval;
	
	select pair_id into strict v_pair_id
	from obanalytics.pairs
	where pair = upper(p_pair);
	
	select exchange_id into strict v_exchange_id
	from obanalytics.exchanges
	where exchange = lower(p_exchange);

	
	v_parent_table := 'matches';
	v_table_name := v_parent_table || '_' || p_exchange;
	i = 1;
	
	v_statements[i] := 'create table if not exists ' || V_SCHEMA || v_table_name || ' partition of '|| V_SCHEMA ||v_parent_table||
						' for values in ('|| v_exchange_id || ') partition by list (pair_id)' ;
						
	i := i+1;
	v_statements[i] := 'alter table ' || V_SCHEMA || v_table_name || ' alter column exchange_id set default ' || v_exchange_id;

	
	v_parent_table := v_table_name;
	v_table_name := v_parent_table || '_' || lower(p_pair);
	i := i + 1;

	v_statements[i] := 'create table if not exists '||V_SCHEMA || v_table_name || ' partition of '|| V_SCHEMA ||v_parent_table||
						' for values in ('|| v_pair_id || ') partition by range (microtimestamp)';

	i := i+1;
	v_statements[i] := 'alter table ' || V_SCHEMA || v_table_name || ' alter column pair_id set default ' || v_pair_id;

	v_parent_table := v_table_name;
	-- We need a shorter name for the leafs - we are confined by max_identifier_length 
	v_table_name :=  'matches_' || lpad(v_exchange_id::text, 2,'0') || lpad(v_pair_id::text, 3,'0') || p_year || lpad(p_month::text, 2, '0') ;
	i := i + 1;
	
	v_statements[i] := 'create table if not exists data.'||v_table_name||' partition of '||V_SCHEMA ||v_parent_table||
							' for values from ('||quote_literal(v_from::timestamptz)||') to (' ||quote_literal(v_to::timestamptz) || ')';
							
							
	i := i + 1;
	v_statements[i] := 'create trigger '||v_table_name||'_bz_save_exchange_microtimestamp before update of microtimestamp on data.'||v_table_name||
		' for each row execute procedure obanalytics.save_exchange_microtimestamp()';
	
	i := i+1;
	v_statements[i] := 'alter table data.' || v_table_name || ' alter column exchange_id set default ' || v_exchange_id;

	i := i+1;
	v_statements[i] := 'alter table data.' || v_table_name || ' alter column pair_id set default ' || v_pair_id;
	
	v_statement := 	'alter table data.' || v_table_name || ' add constraint '  || v_table_name ;

	i := i+1;
	v_statements[i] := v_statement || '_unique_order_ids_combination unique (buy_order_id, sell_order_id) ';
	
	v_buy_orders_table :=  'level3_' || lpad(v_exchange_id::text, 2,'0') || lpad(v_pair_id::text, 3,'0') || 'b' ||  p_year || lpad(p_month::text, 2, '0') ;	
	v_sell_orders_table :=  'level3_' || lpad(v_exchange_id::text, 2,'0') || lpad(v_pair_id::text, 3,'0') || 's' ||  p_year || lpad(p_month::text, 2, '0') ;	

	i := i + 1;
	v_statements[i] := v_statement || '_fkey_level3_buys  foreign key (buy_event_no, microtimestamp, buy_order_id) references data.'||v_buy_orders_table ||
							'(event_no, microtimestamp, order_id) match simple on update cascade on delete no action deferrable initially deferred';
							
	i := i + 1;
	v_statements[i] := v_statement || '_fkey_level3_sells  foreign key (sell_event_no, microtimestamp, sell_order_id) references data.' ||v_sell_orders_table ||
							'(event_no, microtimestamp, order_id) match simple on update cascade on delete no action deferrable initially deferred';

	i := i+1;
	v_statements[i] := 'alter table data.' || v_table_name || ' set ( autovacuum_vacuum_scale_factor= 0.0 , autovacuum_vacuum_threshold = 10000)';
	

	foreach v_statement in array v_statements loop
		raise debug '%', v_statement;
		if p_execute then 
			execute v_statement;
		end if;		
	end loop;		
	return;
end;

$$;


ALTER FUNCTION obanalytics._create_matches_partition(p_exchange text, p_pair text, p_year integer, p_month integer, p_execute boolean) OWNER TO "ob-analytics";

--
-- Name: _depth_after_depth_change(obanalytics.level2_depth_record[], obanalytics.level2_depth_record[], timestamp with time zone, integer, integer); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics._depth_after_depth_change(p_depth obanalytics.level2_depth_record[], p_depth_change obanalytics.level2_depth_record[], p_microtimestamp timestamp with time zone, p_pair_id integer, p_exchange_id integer) RETURNS obanalytics.level2_depth_record[]
    LANGUAGE plpgsql
    AS $$
begin 
	
	if p_depth is null then
		p_depth := array(	select row(price,  
											sum(amount),
									   		side,
									   		null
										 )::obanalytics.level2_depth_record
								 from obanalytics.order_book( p_microtimestamp, p_pair_id, p_exchange_id,
															p_only_makers := true,p_before := true) join unnest(ob) on true
								 group by ts, price, side
					  );
	end if;
	return array(  select row(price, volume, side, null)::obanalytics.level2_depth_record
					from (
						select coalesce(d.price, c.price) as price, coalesce(c.volume, d.volume) as volume, coalesce(d.side, c.side) as side
						from unnest(p_depth) d full join unnest(p_depth_change) c using (price, side)
					) a
					where volume <> 0
				 	order by price desc
				);
end;
$$;


ALTER FUNCTION obanalytics._depth_after_depth_change(p_depth obanalytics.level2_depth_record[], p_depth_change obanalytics.level2_depth_record[], p_microtimestamp timestamp with time zone, p_pair_id integer, p_exchange_id integer) OWNER TO "ob-analytics";

--
-- Name: _depth_change(obanalytics.pair_of_ob); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics._depth_change(p_obs obanalytics.pair_of_ob) RETURNS obanalytics.level2_depth_record[]
    LANGUAGE sql
    AS $$
select * from obanalytics._depth_change(
	coalesce(p_obs.ob1,
			 coalesce ( (   select ob 
							from obanalytics.order_book( ( select max(microtimestamp) from unnest(p_obs.ob2)),	-- ob's ts is max(microtimestamp), see order_book() code
														  ( select pair_id from unnest(p_obs.ob2) limit 1),
														  ( select exchange_id from unnest(p_obs.ob2) limit 1),
														  p_only_makers := true,
														  p_before := true,	-- we need ob BEFORE here
														  p_check_takers := true))),
			 			p_obs.ob2 ),
			  p_obs.ob2);

$$;


ALTER FUNCTION obanalytics._depth_change(p_obs obanalytics.pair_of_ob) OWNER TO "ob-analytics";

--
-- Name: _depth_change(obanalytics.level3[], obanalytics.level3[]); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics._depth_change(p_ob_before obanalytics.level3[], p_ob_after obanalytics.level3[]) RETURNS obanalytics.level2_depth_record[]
    LANGUAGE sql
    AS $$select array_agg(row(price, coalesce(af.amount, 0), side, null::integer)::obanalytics.level2_depth_record  order by price, side)
from (
	select a.price, sum(a.amount) as amount,a.side
	from unnest(p_ob_before) a 
	-- where a.is_maker 
	group by a.price, a.side, a.pair_id
) bf full join (
	select a.price, sum(a.amount) as amount, a.side
	from unnest(p_ob_after) a 
	-- where a.is_maker 
	group by a.price, a.side, a.pair_id
) af using (price, side)
where bf.amount is distinct from af.amount$$;


ALTER FUNCTION obanalytics._depth_change(p_ob_before obanalytics.level3[], p_ob_after obanalytics.level3[]) OWNER TO "ob-analytics";

--
-- Name: _depth_change_sfunc(obanalytics.pair_of_ob, obanalytics.level3[]); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics._depth_change_sfunc(p_obs obanalytics.pair_of_ob, p_ob obanalytics.level3[]) RETURNS obanalytics.pair_of_ob
    LANGUAGE sql STABLE
    AS $$
	select (p_obs.ob2, p_ob)::obanalytics.pair_of_ob;

$$;


ALTER FUNCTION obanalytics._depth_change_sfunc(p_obs obanalytics.pair_of_ob, p_ob obanalytics.level3[]) OWNER TO "ob-analytics";

--
-- Name: _depth_summary(obanalytics.level2_depth_summary_internal_state); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics._depth_summary(p_depth obanalytics.level2_depth_summary_internal_state) RETURNS obanalytics.level2_depth_record[]
    LANGUAGE sql STABLE
    AS $$

with depth as (
	select price, volume, side
	from unnest(p_depth.full_depth) d
),	
depth_with_best_prices as (
	select min(price) filter(where side = 's') over () as best_ask_price, 
			max(price) filter(where side = 'b') over () as best_bid_price, 
			price,
			volume as amount,
			side
	from depth
),
depth_with_bps_levels as (
	select amount, 
			price,
			side,
			case side
				when 's' then ceiling((price-best_ask_price)/best_ask_price/p_depth.bps_step*10000)::numeric	
				when 'b' then ceiling((best_bid_price-price)/best_bid_price/p_depth.bps_step*10000)::numeric	
			end*p_depth.bps_step as bps_level,
			best_ask_price,
			best_bid_price
	from depth_with_best_prices
),
depth_with_price_adjusted as (
	select amount,
			case side
				when 's' then round(best_ask_price*(1 + bps_level/10000), (select "R0" from obanalytics.pairs where pair_id = p_depth.pair_id)) 
				when 'b' then round(best_bid_price*(1 - bps_level/10000), (select "R0" from obanalytics.pairs where pair_id = p_depth.pair_id)) 
			end as price,
			side,
			bps_level
	from depth_with_bps_levels 
	where bps_level <= p_depth.max_bps_level
),
depth_summary as (
	select price, 
			sum(amount), 
			side, 
			bps_level::bigint
	from depth_with_price_adjusted
	group by 1, 3, 4
)
select array_agg(depth_summary::obanalytics.level2_depth_record)
from depth_summary

$$;


ALTER FUNCTION obanalytics._depth_summary(p_depth obanalytics.level2_depth_summary_internal_state) OWNER TO "ob-analytics";

--
-- Name: _depth_summary_after_depth_change(obanalytics.level2_depth_summary_internal_state, obanalytics.level2_depth_record[], timestamp with time zone, integer, integer, integer, integer); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics._depth_summary_after_depth_change(p_internal_state obanalytics.level2_depth_summary_internal_state, p_depth_change obanalytics.level2_depth_record[], p_microtimestamp timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_bps_step integer, p_max_bps_level integer) RETURNS obanalytics.level2_depth_summary_internal_state
    LANGUAGE sql STABLE
    AS $$
select obanalytics._depth_after_depth_change(p_internal_state.full_depth, p_depth_change, p_microtimestamp, p_pair_id, p_exchange_id),
		p_bps_step, 
		p_max_bps_level,
		p_pair_id::smallint;
$$;


ALTER FUNCTION obanalytics._depth_summary_after_depth_change(p_internal_state obanalytics.level2_depth_summary_internal_state, p_depth_change obanalytics.level2_depth_record[], p_microtimestamp timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_bps_step integer, p_max_bps_level integer) OWNER TO "ob-analytics";

--
-- Name: _drop_leaf_level2_partition(text, text, character, integer, integer, boolean); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics._drop_leaf_level2_partition(p_exchange text, p_pair text, p_precision character, p_year integer, p_month integer, p_execute boolean DEFAULT false) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$

declare
	i integer;
	v_exchange_id smallint;
	v_pair_id smallint;
	
	v_table_name text;
	v_statement text;
	v_statements text[];
	V_SCHEMA constant text default 'obanalytics.';
begin 

	if not lower(p_precision) in ('r0', 'p0', 'p1', 'p2', 'p3', 'p4') then 
		raise exception 'Invalid p_precision: %. Valid values are r0, p1, p2, p3, p4', p_precision;
	end if;

	select pair_id into strict v_pair_id
	from obanalytics.pairs
	where pair = upper(p_pair);
	
	select exchange_id into strict v_exchange_id
	from obanalytics.exchanges
	where exchange = lower(p_exchange);

	v_table_name :=  'level2_' || lpad(v_exchange_id::text, 2,'0') || lpad(v_pair_id::text, 3,'0')|| p_precision || p_year || lpad(p_month::text, 2, '0') ;
	i := 1;
	
	v_statements[i] := 'drop table if exists '||V_SCHEMA ||v_table_name;
							
	foreach v_statement in array v_statements loop
		if p_execute then 
			raise log '%', v_statement;
			execute v_statement;
		else
			raise debug '%', v_statement;
		end if;		
	end loop;		
	return;
end;

$$;


ALTER FUNCTION obanalytics._drop_leaf_level2_partition(p_exchange text, p_pair text, p_precision character, p_year integer, p_month integer, p_execute boolean) OWNER TO "ob-analytics";

--
-- Name: _drop_leaf_level3_partition(text, character, text, integer, integer, boolean); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics._drop_leaf_level3_partition(p_exchange text, p_side character, p_pair text, p_year integer, p_month integer, p_execute boolean DEFAULT false) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$

declare
	i integer;
	v_exchange_id smallint;
	v_pair_id smallint;
	
	v_table_name text;
	v_statement text;
	v_statements text[];
	V_SCHEMA constant text default 'obanalytics.';
begin 

	if not lower(p_side) in ('b', 's') then 
		raise exception 'Invalid p_side: % ', p_side;
	end if;
	
	select pair_id into strict v_pair_id
	from obanalytics.pairs
	where pair = upper(p_pair);
	
	select exchange_id into strict v_exchange_id
	from obanalytics.exchanges
	where exchange = lower(p_exchange);

	v_table_name :=  'level3_' || lpad(v_exchange_id::text, 2,'0') || lpad(v_pair_id::text, 3,'0')|| p_side || p_year || lpad(p_month::text, 2, '0') ;
	i := 1;
	
	v_statements[i] := 'drop table if exists '||V_SCHEMA ||v_table_name;
							
	foreach v_statement in array v_statements loop
		if p_execute then 
			raise log '%', v_statement;
			execute v_statement;
		else
			raise debug '%', v_statement;
		end if;		
	end loop;		
	return;
end;

$$;


ALTER FUNCTION obanalytics._drop_leaf_level3_partition(p_exchange text, p_side character, p_pair text, p_year integer, p_month integer, p_execute boolean) OWNER TO "ob-analytics";

--
-- Name: _drop_leaf_matches_partition(text, text, integer, integer, boolean); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics._drop_leaf_matches_partition(p_exchange text, p_pair text, p_year integer, p_month integer, p_execute boolean DEFAULT false) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$

declare
	i integer;
	v_exchange_id smallint;
	v_pair_id smallint;
	
	
	v_table_name text;
	v_statement text;
	v_statements text[];
	V_SCHEMA constant text default 'obanalytics.';
begin 

	select pair_id into strict v_pair_id
	from obanalytics.pairs
	where pair = upper(p_pair);
	
	select exchange_id into strict v_exchange_id
	from obanalytics.exchanges
	where exchange = lower(p_exchange);
	
	v_table_name :=  'matches_' || lpad(v_exchange_id::text, 2,'0') || lpad(v_pair_id::text, 3,'0') || p_year || lpad(p_month::text, 2, '0') ;
	i := 1;
	
	v_statements[i] := 'drop table if exists '||V_SCHEMA ||v_table_name;
							
	foreach v_statement in array v_statements loop
		raise debug '%', v_statement;
		if p_execute then 
			execute v_statement;
		end if;		
	end loop;		
	return;
end;

$$;


ALTER FUNCTION obanalytics._drop_leaf_matches_partition(p_exchange text, p_pair text, p_year integer, p_month integer, p_execute boolean) OWNER TO "ob-analytics";

--
-- Name: _is_valid_taker_event(timestamp with time zone, bigint, integer, integer, integer, timestamp with time zone); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics._is_valid_taker_event(p_microtimestamp timestamp with time zone, p_order_id bigint, p_event_no integer, p_pair_id integer, p_exchange_id integer, p_next_microtimestamp timestamp with time zone) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
begin 
	if p_next_microtimestamp = '-infinity' then
		return true;
	else
		raise exception 'Invalid taker event: % % % % %', p_microtimestamp, p_order_id, p_event_no, 
				(select pair from obanalytics.pairs where pair_id = p_pair_id),
				(select exchange from obanalytics.exchanges where exchange_id = p_exchange_id);
	end if;				
end;
$$;


ALTER FUNCTION obanalytics._is_valid_taker_event(p_microtimestamp timestamp with time zone, p_order_id bigint, p_event_no integer, p_pair_id integer, p_exchange_id integer, p_next_microtimestamp timestamp with time zone) OWNER TO "ob-analytics";

--
-- Name: _level3_uuid(timestamp with time zone, bigint, integer, smallint, smallint); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics._level3_uuid(p_microtimestamp timestamp with time zone, p_order_id bigint, p_event_no integer, p_pair_id smallint, p_exchange_id smallint) RETURNS uuid
    LANGUAGE sql IMMUTABLE
    AS $$select md5(p_microtimestamp::text||'#'||p_order_id::text||'#'||p_event_no::text||'#'||p_exchange_id||'#'||p_pair_id)::uuid;$$;


ALTER FUNCTION obanalytics._level3_uuid(p_microtimestamp timestamp with time zone, p_order_id bigint, p_event_no integer, p_pair_id smallint, p_exchange_id smallint) OWNER TO "ob-analytics";

--
-- Name: _order_book_after_episode(obanalytics.level3[], obanalytics.level3[], boolean); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics._order_book_after_episode(p_ob obanalytics.level3[], p_ep obanalytics.level3[], p_check_takers boolean) RETURNS obanalytics.level3[]
    LANGUAGE plpgsql STABLE
    AS $$begin
	if p_ob is null then
		select ob into p_ob
		from obanalytics.order_book(p_ep[1].microtimestamp, p_ep[1].pair_id, p_ep[1].exchange_id, p_only_makers := false, p_before := true, p_check_takers := p_check_takers );
	end if;
	
	return ( with mix as (
						select ob.*, false as is_deleted
						from unnest(p_ob) ob
						union all
						select ob.*, next_microtimestamp = '-infinity'::timestamptz as is_deleted
						from unnest(p_ep) ob
					),
					latest_events as (
						select distinct on (order_id) *
						from mix
						order by order_id, event_no desc	-- just take the latest event_no for each order
					),
					orders as (
					select microtimestamp, order_id, event_no, side, price, amount, fill, next_microtimestamp, next_event_no, pair_id, exchange_id, local_timestamp,
							price_microtimestamp, price_event_no, exchange_microtimestamp, 
							coalesce(
								case side
									when 'b' then price <= min(price) filter (where side = 's' and amount > 0 ) over (order by price_microtimestamp, microtimestamp)
									when 's' then price >= max(price) filter (where side = 'b' and amount > 0 ) over (order by price_microtimestamp, microtimestamp)
								end,
							true) -- if there are only 'buy' or 'sell' orders in the order book at some moment in time, then all of them are makers
							as is_maker,
							coalesce(
								case side 
									when 'b' then price > min(price) filter (where side = 's' and amount > 0 ) over (order by price_microtimestamp desc, microtimestamp desc)
									when 's' then price < max(price) filter (where side = 'b' and amount > 0 ) over (order by price_microtimestamp desc, microtimestamp desc)
								end,
							false )	-- if there are only 'b' or 's' orders in the order book at some moment in time, then all of them are not crossed
							as is_crossed
					from latest_events
					where not is_deleted
				)
				select array(
					select orders::obanalytics.level3
					from orders
					where not p_check_takers 
					    or (is_maker or (not is_maker and obanalytics._is_valid_taker_event(microtimestamp, order_id, event_no, pair_id, exchange_id, next_microtimestamp)))
					order by price, microtimestamp, order_id, event_no 
					-- order by must be the same as in obanalytics.order_book(). Change both!					
				));
end;   

$$;


ALTER FUNCTION obanalytics._order_book_after_episode(p_ob obanalytics.level3[], p_ep obanalytics.level3[], p_check_takers boolean) OWNER TO "ob-analytics";

--
-- Name: _periods_within_eras(timestamp with time zone, timestamp with time zone, integer, integer, interval); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics._periods_within_eras(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_frequency interval) RETURNS TABLE(period_start timestamp with time zone, period_end timestamp with time zone, previous_period_end timestamp with time zone)
    LANGUAGE sql
    AS $$	select period_start, period_end, lag(period_end) over (order by period_start) as previous_period_end
	from (
		select period_start, period_end
		from (
			select greatest(get._date_ceiling(era, p_frequency),
							  get._date_floor(p_start_time, p_frequency)
						   ) as period_start, 
					least(
						least(	-- if get._date_ceiling(level3, p_frequency) overlaps with the next era, will effectively take get._date_floor(level3, p_frequency)!
							coalesce( get._date_ceiling(level3, p_frequency),
								   	   get._date_ceiling(era, p_frequency)
									  ),
							get._date_floor( coalesce( lead(era) over (order by era), 'infinity') , p_frequency)
						),
						get._date_floor(p_end_time, p_frequency)
					) as period_end
			from obanalytics.level3_eras
			where pair_id = p_pair_id
			  and exchange_id = p_exchange_id
			  and get._date_floor(p_start_time, p_frequency) <= coalesce(get._date_floor(level3, p_frequency), get._date_ceiling(era, p_frequency))
			  and get._date_floor(p_end_time, p_frequency) >= get._date_ceiling(era, p_frequency)
		) e
		where get._date_floor(period_end, p_frequency) > get._date_floor(period_start, p_frequency)
	) p
$$;


ALTER FUNCTION obanalytics._periods_within_eras(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_frequency interval) OWNER TO "ob-analytics";

--
-- Name: _recreate_level3_triggers(); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics._recreate_level3_triggers() RETURNS void
    LANGUAGE sql
    AS $$
-- NOTE: This function is a workaround for https://www.postgresql.org/message-id/6b3f0646-ba8c-b3a9-c62d-1c6651a1920f%40phystech.edu
-- 		 Need to be run after addition of a new partition table to the  obanalytics.level3 hierarchy

lock obanalytics.level3 in share row exclusive mode;

-- obanalytics.level3

DROP TRIGGER check_microtimestamp_change ON obanalytics.level3;
CREATE CONSTRAINT TRIGGER check_microtimestamp_change
    AFTER UPDATE OF microtimestamp
    ON obanalytics.level3
    DEFERRABLE INITIALLY DEFERRED    FOR EACH ROW
    EXECUTE PROCEDURE obanalytics.check_microtimestamp_change();

DROP TRIGGER propagate_microtimestamp_change ON obanalytics.level3;
CREATE TRIGGER propagate_microtimestamp_change
    AFTER UPDATE OF microtimestamp
    ON obanalytics.level3
    FOR EACH ROW
    WHEN ((old.exchange_id = 2))
    EXECUTE PROCEDURE obanalytics.propagate_microtimestamp_change();
	
DROP TRIGGER update_chain_after_delete ON obanalytics.level3;	
CREATE TRIGGER update_chain_after_delete
    AFTER DELETE
    ON obanalytics.level3
    FOR EACH ROW
    EXECUTE PROCEDURE obanalytics.level3_update_chain_after_delete();
	
-- obanalytics.level3_bitstamp

DROP TRIGGER check_after_insert ON obanalytics.level3_bitstamp;	
CREATE TRIGGER check_after_insert
    AFTER INSERT
    ON obanalytics.level3_bitstamp
    FOR EACH ROW
    EXECUTE PROCEDURE obanalytics.level3_bitstamp_check_after_insert();

$$;


ALTER FUNCTION obanalytics._recreate_level3_triggers() OWNER TO "ob-analytics";

--
-- Name: _spread_from_depth(obanalytics.level2[]); Type: FUNCTION; Schema: obanalytics; Owner: postgres
--

CREATE FUNCTION obanalytics._spread_from_depth(p_depth obanalytics.level2[]) RETURNS obanalytics.level1
    LANGUAGE sql IMMUTABLE
    AS $$
with price_levels as (
	select side,
			price,
			volume as qty, 
			case side
					when 's' then price is not distinct from min(price) filter (where side = 's') over ()
					when 'b' then price is not distinct from max(price) filter (where side = 'b') over ()
			end as is_best,
			pair_id,
			exchange_id,
			microtimestamp
	from unnest(p_depth)
)
select b.price, b.qty, s.price, s.qty, microtimestamp, pair_id, exchange_id
from (select * from price_levels where side = 'b' and is_best) b full join 
	  (select * from price_levels where side = 's' and is_best) s using (microtimestamp, exchange_id, pair_id);

$$;


ALTER FUNCTION obanalytics._spread_from_depth(p_depth obanalytics.level2[]) OWNER TO postgres;

--
-- Name: _spread_from_depth(timestamp with time zone, obanalytics.level2[]); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics._spread_from_depth(p_ts timestamp with time zone, p_depth obanalytics.level2[]) RETURNS obanalytics.level1
    LANGUAGE sql IMMUTABLE
    AS $$
with price_levels as (
	select side,
			price,
			volume as qty, 
			case side
					when 's' then price is not distinct from min(price) filter (where side = 's') over ()
					when 'b' then price is not distinct from max(price) filter (where side = 'b') over ()
			end as is_best,
			pair_id,
			exchange_id
	from unnest(p_depth)
)
select b.price, b.qty, s.price, s.qty, p_ts, pair_id, exchange_id
from (select * from price_levels where side = 'b' and is_best) b full join 
	  (select * from price_levels where side = 's' and is_best) s using (exchange_id, pair_id);

$$;


ALTER FUNCTION obanalytics._spread_from_depth(p_ts timestamp with time zone, p_depth obanalytics.level2[]) OWNER TO "ob-analytics";

--
-- Name: _spread_from_order_book(timestamp with time zone, obanalytics.level3[]); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics._spread_from_order_book(p_ts timestamp with time zone, p_order_book obanalytics.level3[]) RETURNS obanalytics.level1
    LANGUAGE sql IMMUTABLE
    AS $$
with price_levels as (
	select side,
			price,
			sum(amount) as qty, 
			case side
					when 's' then price is not distinct from min(price) filter (where side = 's') over ()
					when 'b' then price is not distinct from max(price) filter (where side = 'b') over ()
			end as is_best,
			pair_id,
			exchange_id
	from unnest(p_order_book)
	--where is_maker
	group by exchange_id, pair_id,side, price
)
select b.price, b.qty, s.price, s.qty, p_ts, pair_id, exchange_id
from (select * from price_levels where side = 'b' and is_best) b full join 
	  (select * from price_levels where side = 's' and is_best) s using (exchange_id, pair_id);

$$;


ALTER FUNCTION obanalytics._spread_from_order_book(p_ts timestamp with time zone, p_order_book obanalytics.level3[]) OWNER TO "ob-analytics";

--
-- Name: _to_microseconds(timestamp with time zone); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics._to_microseconds(p_timestamptz timestamp with time zone) RETURNS bigint
    LANGUAGE c
    AS '$libdir/libobadiah_db.so.1', 'to_microseconds';


ALTER FUNCTION obanalytics._to_microseconds(p_timestamptz timestamp with time zone) OWNER TO "ob-analytics";

--
-- Name: check_microtimestamp_change(); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.check_microtimestamp_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ 
BEGIN
	if  new.microtimestamp > old.microtimestamp + make_interval(secs := parameters.max_microtimestamp_change(old.pair_id, old.exchange_id)) or
		new.microtimestamp < old.microtimestamp then	
		raise exception 'An attempt to move % % % % % to % is blocked', old.microtimestamp, old.order_id, old.event_no, old.pair_id, old.exchange_id, new.microtimestamp;
	end if;
	return null;
END;
	

$$;


ALTER FUNCTION obanalytics.check_microtimestamp_change() OWNER TO "ob-analytics";

--
-- Name: crossed_books(timestamp with time zone, timestamp with time zone, integer, integer); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.crossed_books(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer) RETURNS TABLE(previous_uncrossed timestamp with time zone, first_crossed timestamp with time zone, next_uncrossed timestamp with time zone, pair_id smallint, exchange_id smallint)
    LANGUAGE sql
    AS $$


with level1 as (
	select coalesce(best_bid_price, best_ask_price) as best_bid_price,
			coalesce(best_ask_price, best_bid_price) as best_ask_price,
			microtimestamp
	from obanalytics.level1_continuous(p_start_time, p_end_time, p_pair_id, p_exchange_id)
),
spread_periods as (
	select min(microtimestamp) as period_start, max(microtimestamp) as period_end, g % 2 = 1 as crossed
	from (
		select *, sum(t) over (order by microtimestamp) as g
		from (
			select * , coalesce(not ((lag(best_bid_price) over(order by microtimestamp) > lag(best_ask_price ) over (order by microtimestamp)) = (best_bid_price > best_ask_price)),best_bid_price > best_ask_price)::integer as t
			from level1
		) a
	) a
	group by g
	order by g
),
spread_periods_chain as (
	select *,lag(period_end) over w as previous_end, lead(period_start) over w as next_start
	from spread_periods
	window w as (order by period_start)
)
select previous_end, period_start, next_start, p_pair_id::smallint, p_exchange_id::smallint
from spread_periods_chain
where crossed 
  and coalesce(previous_end, period_start) < p_end_time
;  
$$;


ALTER FUNCTION obanalytics.crossed_books(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer) OWNER TO "ob-analytics";

--
-- Name: depth_change_by_episode_fast(timestamp with time zone, timestamp with time zone, integer, integer, interval); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.depth_change_by_episode_fast(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_frequency interval DEFAULT NULL::interval) RETURNS SETOF obanalytics.level2
    LANGUAGE c
    AS '$libdir/libobadiah_db.so.1', 'depth_change_by_episode';


ALTER FUNCTION obanalytics.depth_change_by_episode_fast(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_frequency interval) OWNER TO "ob-analytics";

--
-- Name: depth_change_by_episode_slow(timestamp with time zone, timestamp with time zone, integer, integer, boolean); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.depth_change_by_episode_slow(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_check_takers boolean DEFAULT true) RETURNS SETOF obanalytics.level2
    LANGUAGE plpgsql STABLE
    AS $$-- ARGUMENTS
--		p_start_time - the start of the interval for the calculation of depths
--		p_end_time	 - the end of the interval
--		p_pair_id	 - the id of pair for which depths will be calculated
--		p_exchange_id - the id of exchange where depths will be calculated
-- NOTE
--		Precision of depth is P0, i.e. not rounded prices are used
declare
	v_ob_before record;
	v_ob record;
begin
	
	select ts, ob 
	from obanalytics.order_book(p_start_time, p_pair_id, p_exchange_id, p_only_makers := false, p_before := true) 
	into v_ob_before;	-- so there will be a depth_change generated for the very first episode greater or equal to p_start_time
	
	for v_ob in select ts, ob from obanalytics.order_book_by_episode(p_start_time, p_end_time, p_pair_id, p_exchange_id, p_check_takers) 
	loop
		if v_ob_before is not null then -- if p_start_time equals to an era start then v_ob_before will be null 
										 -- so we don't generate depth_change for the era start
													 
			return query 
				select v_ob.ts, p_pair_id::smallint, p_exchange_id::smallint,'r0'::character(2),  l2.*
				from obanalytics._depth_change(v_ob_before.ob, v_ob.ob) d join unnest(d) l2 on true;
		end if;
		v_ob_before := v_ob;
	end loop;			
end;

$$;


ALTER FUNCTION obanalytics.depth_change_by_episode_slow(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_check_takers boolean) OWNER TO "ob-analytics";

--
-- Name: fix_crossed_books(timestamp with time zone, integer, integer); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.fix_crossed_books(p_ts_within_era timestamp with time zone, p_pair_id integer, p_exchange_id integer) RETURNS SETOF obanalytics.level3
    LANGUAGE plpgsql
    AS $$
declare
	v_era_start timestamptz;
	v_era_end timestamptz;
begin

	select era, level3 into strict v_era_start, v_era_end
	from obanalytics.level3_eras
	where p_ts_within_era between era and level3
	  and pair_id = p_pair_id
	  and exchange_id = p_exchange_id;
	return query
	select * from obanalytics.fix_crossed_books(v_era_start, v_era_end, p_pair_id, p_exchange_id);
end;
$$;


ALTER FUNCTION obanalytics.fix_crossed_books(p_ts_within_era timestamp with time zone, p_pair_id integer, p_exchange_id integer) OWNER TO "ob-analytics";

--
-- Name: fix_crossed_books(timestamp with time zone, timestamp with time zone, integer, integer); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.fix_crossed_books(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer) RETURNS SETOF obanalytics.level3
    LANGUAGE plpgsql
    AS $$-- NOTE:
--		This function is supposed to be doing something useful only after pga_spread() is failed due to crossed order book
--		It is expected that Bitfinex produces rather few 'bad' events and rarely, so order book is crossed for relatively short
-- 		period of time (i.e. 5 minutes). Otherwise one has to run this function manually, with higher p_max_interval

declare 
	v_current_timestamp timestamptz;
	v_something_was_fixed boolean default true;
	v_crossed timestamptz;
	v_start timestamptz;
	v_end timestamptz;
	v_processing_interval interval default '30 minutes';
	
begin 
	v_current_timestamp := clock_timestamp();
	raise debug 'Started fix_crossed_books(%, %, %, %)', p_start_time, p_end_time, p_pair_id, p_exchange_id;
	v_crossed := p_start_time;
	v_start := p_start_time;
	v_end := p_start_time + v_processing_interval;
	
	if v_end > p_end_time then
		v_end := p_end_time;
	end if;
	
	while v_end <= p_end_time and v_crossed < p_end_time loop
		raise debug 'Processing period: % - % ', v_crossed, v_end;
		while (v_something_was_fixed) loop
			v_something_was_fixed := false;

			for v_crossed in select first_crossed from obanalytics.crossed_books(v_crossed, v_end, p_pair_id, p_exchange_id) loop

				-- Fix eternal takers, which should have been removed by an exchange, but weren't for some reasons
				return query 
					insert into obanalytics.level3 (microtimestamp, order_id, event_no, side, price, amount, fill, next_microtimestamp, next_event_no, pair_id, exchange_id, local_timestamp, price_microtimestamp, price_event_no)
					select distinct on (microtimestamp, order_id)  ts, order_id, 
							null as event_no, -- null here (as well as any null below) should case before row trigger to fire and to update the previous event 
							side, price, amount, fill, '-infinity',
							null as next_event_no,
							pair_id, exchange_id, null as local_timestamp,
							null as price_microtimestamp, 
							null as price_event_no
					from obanalytics.order_book(v_crossed, p_pair_id, p_exchange_id, false, false, false) 
						  join unnest(ob) as ob on true
					where not is_maker and next_microtimestamp = 'infinity'
					returning level3.*;

				if found then 
					v_something_was_fixed := true;
					raise debug 'Fixed eternal takers  - fix_crossed_books(%, %, %)', v_crossed, p_pair_id, p_exchange_id;
					exit;
				end if;


				-- Merge crossed books to the next taker's event if it is exists (i.e. next_microtimestamp is not -infinity)
				return query 		
					with takers as (
						select distinct  on (microtimestamp, order_id, event_no) microtimestamp, order_id, next_microtimestamp, next_event_no
						from obanalytics.order_book(v_crossed, p_pair_id, p_exchange_id, false, false, false)
							  join unnest(ob) as ob on true
						where not is_maker
						  and next_microtimestamp > '-infinity'
						  and next_microtimestamp <= microtimestamp + make_interval(secs := parameters.max_microtimestamp_change(p_pair_id, p_exchange_id))
					),
					merge_intervals as (	-- there may be several takers, so first we need to understand which episodes to merge. 
						select v_crossed as microtimestamp, max(next_microtimestamp) as next_microtimestamp 
						from takers
					)
					select merge_episodes.*
					from merge_intervals join obanalytics.merge_episodes(microtimestamp, next_microtimestamp, p_pair_id, p_exchange_id) on true;

				if found then 
					v_something_was_fixed := true;
					raise debug 'Merged crossed books to the next taker event - fix_crossed_books(%, %, %)', v_crossed, p_pair_id, p_exchange_id;
					exit;
				end if;
				
				-- Fix eternal crossed orders, which should have been removed by an exchange, but weren't for some reasons
				-- Note that we do not check amounts here. Taker could have small amount to remove all makers 
				
				return query 
					insert into obanalytics.level3 (microtimestamp, order_id, event_no, side, price, amount, fill, next_microtimestamp, next_event_no, pair_id, exchange_id, local_timestamp, price_microtimestamp, price_event_no)
					select distinct on (microtimestamp, order_id)  ts, order_id, 
							null as event_no, -- null here (as well as any null below) should case before row trigger to fire and to update the previous event 
							side, price, amount, fill, '-infinity',
							null as next_event_no,
							pair_id, exchange_id, null as local_timestamp,
							null as price_microtimestamp, 
							null as price_event_no
					from obanalytics.order_book(v_crossed, p_pair_id, p_exchange_id, false, false, false) 
						  join unnest(ob) as ob on true
					where is_crossed and next_microtimestamp = 'infinity'
					returning level3.*; 

				if found then 
					v_something_was_fixed := true;
					raise debug 'Fixed eternal crossed orders - fix_crossed_books(%, %, %)', v_crossed, p_pair_id, p_exchange_id;
					exit;
				end if;
			end loop;
		end loop;
		-- Finally, try to merge remaining episodes producing crossed order books
		return query select * from obanalytics.merge_crossed_books(v_start, v_end, p_pair_id, p_exchange_id); 
		v_crossed := v_end;
		v_start := v_end;
		v_something_was_fixed := true;
		v_end := v_end +  v_processing_interval;
		if v_end > p_end_time then
			v_end := p_end_time;
		end if;
	end loop;																			 
	raise debug 'fix_crossed_books() exec time: %', clock_timestamp() - v_current_timestamp;
	return;
end;

$$;


ALTER FUNCTION obanalytics.fix_crossed_books(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer) OWNER TO "ob-analytics";

--
-- Name: level3_eras; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_eras (
    era timestamp with time zone NOT NULL,
    pair_id smallint NOT NULL,
    exchange_id smallint NOT NULL,
    level3 timestamp with time zone
);


ALTER TABLE obanalytics.level3_eras OWNER TO "ob-analytics";

--
-- Name: insert_level3_era(timestamp with time zone, integer, integer); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.insert_level3_era(p_new_era timestamp with time zone, p_pair_id integer, p_exchange_id integer) RETURNS SETOF obanalytics.level3_eras
    LANGUAGE plpgsql
    AS $$
declare
	v_previous_era obanalytics.level3_eras%rowtype;
	v_new_era obanalytics.level3_eras%rowtype;
	v_next_era obanalytics.level3_eras%rowtype;
begin

	select distinct on (pair_id, exchange_id) * into strict v_previous_era 
	from obanalytics.level3_eras
	where pair_id = p_pair_id
	  and exchange_id = p_exchange_id
	  and era <= p_new_era
	order by exchange_id, pair_id, era desc;
	
	select distinct on (pair_id, exchange_id) * into strict v_next_era 
	from obanalytics.level3_eras
	where pair_id = p_pair_id
	  and exchange_id = p_exchange_id
	  and era >= p_new_era
	order by exchange_id, pair_id, era ;
	
	
	if exists (select * 
			    from obanalytics.level1 
			    where microtimestamp >= p_new_era 
			   	  and microtimestamp < v_next_era.era
			      and pair_id = p_pair_id
			      and exchange_id = p_exchange_id ) or
		exists (select * 
			    from obanalytics.level2
			    where microtimestamp >= p_new_era 
				  and microtimestamp < v_next_era.era
			      and pair_id = p_pair_id
			      and exchange_id = p_exchange_id ) then 
		raise exception 'Can not insert new era - clear level1 & level2 first!';
	end if;
	
	if p_new_era = v_previous_era.era or p_new_era = v_next_era.era then
		raise exception 'Can not insert new era - already exists!';
	end if;
	
	with recursive to_be_updated as (
		select next_microtimestamp as microtimestamp, order_id, next_event_no as event_no, 2::integer as new_event_no,
				p_new_era as new_price_microtimestamp,	1::integer as new_price_event_no 
		from obanalytics.level3
		where exchange_id = p_exchange_id
		  and pair_id = p_pair_id
		  and microtimestamp >= v_previous_era.era
		  and microtimestamp < p_new_era
		  and next_microtimestamp >= p_new_era
		  and isfinite(next_microtimestamp)
		union all
		select next_microtimestamp, order_id, next_event_no, to_be_updated.new_event_no + 1,
				case when price_microtimestamp < new_price_microtimestamp 
						then new_price_microtimestamp
					  else price_microtimestamp
				end,
				case when price_microtimestamp < new_price_microtimestamp 
						then price_event_no 
					  else event_no
				end
		from (select * from obanalytics.level3 
			   where microtimestamp >= p_new_era
				 and microtimestamp < v_next_era.era
				 and exchange_id = p_exchange_id
				 and pair_id = p_pair_id
			  ) level3 join to_be_updated using (microtimestamp, order_id, event_no)
		where isfinite(next_microtimestamp)
	)
	update obanalytics.level3
	   set event_no = to_be_updated.new_event_no,
	   	    price_microtimestamp = to_be_updated.new_price_microtimestamp,
			price_event_no = to_be_updated.new_price_event_no
	from to_be_updated
	where level3.pair_id = p_pair_id
	  and level3.exchange_id = p_exchange_id
	  and level3.microtimestamp >= p_new_era
	  and level3.microtimestamp < v_next_era.era
	  and level3.microtimestamp = to_be_updated.microtimestamp
	  and level3.order_id = to_be_updated.order_id
	  and level3.event_no = to_be_updated.event_no;
	
	insert into obanalytics.level3 (microtimestamp, order_id, event_no, side, price, amount, fill, next_microtimestamp, next_event_no, 
								     pair_id, exchange_id, local_timestamp, price_microtimestamp, price_event_no, exchange_microtimestamp)
	select p_new_era,
			order_id,
			1,				-- event_no: must be always 1
			side, 
			price, 
			amount, 
			fill,
			next_microtimestamp, 
			next_event_no,
			pair_id,
			exchange_id,
			null::timestamptz,	--	local_timestamp
			p_new_era,
			1,
			null::timestamptz	-- exchange_timestamp
	from obanalytics.level3
	where pair_id = p_pair_id
	  and exchange_id = p_exchange_id
	  and microtimestamp >= v_previous_era.era 
	  and microtimestamp < p_new_era
	  and next_microtimestamp >= p_new_era
	  and next_microtimestamp < 'infinity';
	  
	update obanalytics.level3	  
	  set next_microtimestamp = 'infinity',
	      next_event_no = null
	where pair_id = p_pair_id
	  and exchange_id = p_exchange_id
	  and microtimestamp >= v_previous_era.era 
	  and microtimestamp < p_new_era
	  and next_microtimestamp >= p_new_era
	  and next_microtimestamp < 'infinity'
	  ;
	  
	update obanalytics.level3_eras
	  set  level2 = (select max(microtimestamp) 
					from obanalytics.level2
					where pair_id = p_pair_id
				      and exchange_id = p_exchange_id
				      and microtimestamp >= v_previous_era.era
				      and microtimestamp < p_new_era),
	   	    level1 = (select max(microtimestamp) 
					from obanalytics.level1
					where pair_id = p_pair_id
				      and exchange_id = p_exchange_id
				      and microtimestamp >= v_previous_era.era
				      and microtimestamp < p_new_era),
	  		 level3 = (select max(microtimestamp) 
					from obanalytics.level3
					where pair_id = p_pair_id
				      and exchange_id = p_exchange_id
				      and microtimestamp >= v_previous_era.era
				      and microtimestamp < p_new_era)
	where era = v_previous_era.era
	  and pair_id = p_pair_id
	  and exchange_id = p_exchange_id;
	  
    insert into obanalytics.level3_eras (era, pair_id, exchange_id, level3)	  
	values (p_new_era, p_pair_id, p_exchange_id, (select max(microtimestamp)
					   	 from obanalytics.level3
					     where pair_id = p_pair_id
					       and exchange_id = p_exchange_id
					       and microtimestamp >= p_new_era
					       and microtimestamp < v_next_era.era ));
	return query select *
				  from obanalytics.level3_eras
				  where pair_id = p_pair_id
				    and exchange_id = p_exchange_id
					and era between v_previous_era.era and v_next_era.era;
	return;
end;
$$;


ALTER FUNCTION obanalytics.insert_level3_era(p_new_era timestamp with time zone, p_pair_id integer, p_exchange_id integer) OWNER TO "ob-analytics";

--
-- Name: level1_continuous(timestamp with time zone, timestamp with time zone, integer, integer, interval); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.level1_continuous(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_frequency interval DEFAULT NULL::interval) RETURNS SETOF obanalytics.level1
    LANGUAGE sql STABLE
    AS $$-- NOTE:

with periods as (
	select * 
	from obanalytics._periods_within_eras(p_start_time, p_end_time, p_pair_id, p_exchange_id, p_frequency)
)
select level1.*
from periods join obanalytics.spread_by_episode_fast(period_start, period_end, p_pair_id, p_exchange_id, p_frequency) level1 on true 
  ;

$$;


ALTER FUNCTION obanalytics.level1_continuous(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_frequency interval) OWNER TO "ob-analytics";

--
-- Name: level2_continuous(timestamp with time zone, timestamp with time zone, integer, integer, interval); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.level2_continuous(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_frequency interval DEFAULT NULL::interval) RETURNS SETOF obanalytics.level2
    LANGUAGE sql STABLE
    AS $$-- NOTE:
--	When 'microtimestamp' in returned record 
--		1. equals to 'p_start_time' and equals to some 'era' from obanalytics.level3_eras then 'depth_change' is a full depth from obanalytics.order_book(microtimestamp)
--		2. equals to 'p_start_time' and in the middle of an era or 
--		   'microtimestamp' > p_start_time and <= p_end_time and equals to some 'era' then 
--			'depth_change' is _depth_change(ob1, ob2) where ob1 = order_book(microtimestamp - '00:00:00.000001') and ob2 = order_book(microtimestamp)
--		3. Otherwise 'depth_change' is from corresponding obanalytics.level2 record
--	It is not possible to use order_book(p_before :=true) as the start of an era since it will be empty!

with periods as (
	select * 
	from obanalytics._periods_within_eras(p_start_time, p_end_time, p_pair_id, p_exchange_id, p_frequency)
),
starting_depth_change as (
	select period_start - '00:00:00.000001'::interval, p_pair_id::smallint, p_exchange_id::smallint, 'r0', (d).*
	from periods join obanalytics.order_book(previous_period_end, p_pair_id,p_exchange_id, false, false,false ) b on true 
				 join obanalytics.order_book(period_start, p_pair_id,p_exchange_id, false, true, false ) a on true 
				 join obanalytics._depth_change(b.ob, a.ob) c on true join unnest(c) d on true
	where previous_period_end is not null 
)
select *
from starting_depth_change
union all 
select level2.*
from periods join obanalytics.depth_change_by_episode_fast(period_start, period_end, p_pair_id, p_exchange_id, p_frequency) level2 on true 
where microtimestamp >= period_start
  and microtimestamp <= period_end
  and level2.pair_id = p_pair_id
  and level2.exchange_id = p_exchange_id 
  and level2.precision = 'r0' 
  ;

$$;


ALTER FUNCTION obanalytics.level2_continuous(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_frequency interval) OWNER TO "ob-analytics";

--
-- Name: level3_bitstamp_check_after_insert(); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.level3_bitstamp_check_after_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$declare
	v_era_start timestamptz;
	v_era_end timestamptz;
	
	v_microtimestamp timestamptz;
	v_order_id bigint;
	v_event_no integer;
	
begin
	
	select max(era) into v_era_start
	from obanalytics.level3_eras
	where pair_id = new.pair_id
	  and exchange_id = new.exchange_id
	  and era <= new.microtimestamp;
	  
	select coalesce(min(era) - '1 microsecond'::interval, 'infinity') into v_era_end
	from obanalytics.level3_eras
	where pair_id = new.pair_id
	  and exchange_id = new.exchange_id
	  and era > new.microtimestamp;
	  
	select microtimestamp, order_id, event_no into v_microtimestamp, v_order_id, v_event_no
	from obanalytics.level3
	where microtimestamp between v_era_start and v_era_end
   	  and pair_id = new.pair_id
	  and exchange_id = new.exchange_id
	  and order_id = new.order_id
	  and new.microtimestamp > microtimestamp 
	  and new.microtimestamp < next_microtimestamp
	limit 1;
	
	if found then 
		raise exception 'New % % % % % overlaps with % % %', new.microtimestamp, new.order_id, new.event_no, new.pair_id, new.exchange_id, v_microtimestamp, v_order_id, v_event_no;
	end if;
	return null;
end;
$$;


ALTER FUNCTION obanalytics.level3_bitstamp_check_after_insert() OWNER TO "ob-analytics";

--
-- Name: level3_eras_delete(); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.level3_eras_delete() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare
	v_next_era timestamptz;
	v_row_count bigint;
begin
	select coalesce(min(era), 'infinity') into v_next_era
	from obanalytics.level3_eras
	where era > old.era
	  and pair_id = old.pair_id
	  and exchange_id = old.exchange_id;
	
	delete from obanalytics.matches 
	where microtimestamp >= old.era 
	  and microtimestamp < v_next_era
	  and pair_id = old.pair_id
	  and exchange_id = old.exchange_id;
	  
	get diagnostics v_row_count = row_count;
	raise notice 'Deleted % rows from obanalytics.matches where microtimestamp >= %  and < % pair_id % exchange_id %', v_row_count,  old.era, v_next_era, old.pair_id, old.exchange_id;
	  
	delete from obanalytics.level3
	where microtimestamp >= old.era 
	  and microtimestamp < v_next_era
	  and pair_id = old.pair_id
	  and exchange_id = old.exchange_id;
	  
	get diagnostics v_row_count = row_count;
	raise notice 'Deleted % rows from obanalytics.level3 where microtimestamp >= %  and < % pair_id % exchange_id %', v_row_count,  old.era, v_next_era, old.pair_id, old.exchange_id;
	
	return null;
end;
$$;


ALTER FUNCTION obanalytics.level3_eras_delete() OWNER TO "ob-analytics";

--
-- Name: level3_incorporate_new_event(); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.level3_incorporate_new_event() RETURNS trigger
    LANGUAGE plpgsql
    AS $$declare
	v_era timestamptz;
	v_amount numeric;
	
	v_event obanalytics.level3;
	
begin

	if new.price_microtimestamp is null or new.event_no is null then 
		raise debug 'Will process  %, %', new.microtimestamp, new.order_id;
	-- The values of the above two columns depend on the previous event for the order_id if any and are mandatory (not null). 
	-- They have to be set by either an inserter of the record (more effective) or by this trigger
		begin
		
			select max(era) into v_era
			from obanalytics.level3_eras
			where pair_id = new.pair_id
			  and exchange_id = new.exchange_id
			  and era <= new.microtimestamp;
		
			update obanalytics.level3
			   set next_microtimestamp = new.microtimestamp,
				   next_event_no = event_no + 1
			where exchange_id = new.exchange_id
			  and pair_id = new.pair_id
			  and microtimestamp between v_era and new.microtimestamp
			  and order_id = new.order_id 
			  and side = new.side
			  and next_microtimestamp > new.microtimestamp
			returning *
			into v_event;
			-- amount, next_event_no INTO v_amount, NEW.event_no;
		exception 
			when too_many_rows then
				raise exception 'too many rows for %, %, %', new.microtimestamp, new.order_id, new.event_no;
		end;
		if found then
		
			if new.price = 0 then 
				new.price = v_event.price;
				new.amount = v_event.amount;
				new.fill = null;
			else
				new.fill := v_event.amount - new.amount; 
			end if;

			new.event_no := v_event.next_event_no;

			if v_event.price = new.price THEN 
				new.price_microtimestamp := v_event.price_microtimestamp;
				new.price_event_no := v_event.price_event_no;
			else	
				new.price_microtimestamp := new.microtimestamp;
				new.price_event_no := new.event_no;
			end if;

		else -- it is the first event for order_id (or first after the latest 'deletion' )
			-- new.fill will remain null. Might set it later from matched trade, if any
			if new.price > 0 then 
				new.price_microtimestamp := new.microtimestamp;
				new.price_event_no := 1;
				new.event_no := 1;
			else
				raise notice 'Skipped insertion of %, %, %, %', new.microtimestamp, new.order_id, new.event_no, new.local_timestamp;
				return null;	-- skip insertion
			end if;
		end if;
		
	end if;
	return new;
end;

$$;


ALTER FUNCTION obanalytics.level3_incorporate_new_event() OWNER TO "ob-analytics";

--
-- Name: level3_update_chain_after_delete(); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.level3_update_chain_after_delete() RETURNS trigger
    LANGUAGE plpgsql
    AS $$begin 
	-- update previous event, if any
	
	if old.event_no > 1 then
	
		update obanalytics.level3
		   set next_microtimestamp = 'infinity',
		       next_event_no = null
		where exchange_id = old.exchange_id
		  and pair_id = old.pair_id
		  and microtimestamp between (	select max(era)
									     from obanalytics.level3_eras
									     where exchange_id = old.exchange_id
									  	   and pair_id = old.pair_id
									       and era <= old.microtimestamp ) and old.microtimestamp
		  and order_id = old.order_id										   
		  and next_microtimestamp = old.microtimestamp
		  and next_event_no = old.event_no;
	 		
	end if;
	
	-- delete next event, if any
	
	if isfinite(old.next_microtimestamp) then
	
		raise debug 'Cascade delete of %, %, % e % p %', old.next_microtimestamp, old.order_id, old.next_event_no, old.exchange_id, old.pair_id;
		delete from  obanalytics.level3
		where exchange_id = old.exchange_id
		  and pair_id = old.pair_id
		  and microtimestamp = old.next_microtimestamp
		  and order_id = old.order_id										   
		  and event_no = old.next_event_no;
	end if;
	return old;
end;$$;


ALTER FUNCTION obanalytics.level3_update_chain_after_delete() OWNER TO "ob-analytics";

--
-- Name: level3_update_level3_eras(); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.level3_update_level3_eras() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin 
	with latest_events as (
		select exchange_id, pair_id, max(microtimestamp) as latest
		from inserted
		group by exchange_id, pair_id
	),
	eras as (
		select exchange_id, pair_id, latest, max(era) as era
		from obanalytics.level3_eras join latest_events using (exchange_id, pair_id)
		where era <= latest
		group by exchange_id, pair_id, latest
	)
	update obanalytics.level3_eras
	   set level3 = latest
	from eras
	where level3_eras.era = eras.era
	  and level3_eras.exchange_id = eras.exchange_id
	  and level3_eras.pair_id = eras.pair_id
	  and (level3 is null or level3 < latest);
	return null;
end;
$$;


ALTER FUNCTION obanalytics.level3_update_level3_eras() OWNER TO "ob-analytics";

--
-- Name: merge_crossed_books(timestamp with time zone, timestamp with time zone, integer, integer); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.merge_crossed_books(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer) RETURNS SETOF obanalytics.level3
    LANGUAGE plpgsql
    AS $$declare 
	crossed_books record;
	v_execution_start_time timestamp with time zone;
begin
	v_execution_start_time := clock_timestamp();
	raise debug 'merge_crossed_books(%, %, %, %)', p_start_time, p_end_time,  p_pair_id, p_exchange_id;

	for crossed_books in (select * from obanalytics.crossed_books(p_start_time, p_end_time, p_pair_id, p_exchange_id) where next_uncrossed is not null) loop
		if crossed_books.next_uncrossed is null then 
			raise exception 'Unable to find next uncrossed order book:  previous_uncrossed=%, pair_id=%, exchange_id=%', crossed_books.previous_uncrossed, p_pair_id, p_exchange_id;
		end if;
		if crossed_books.first_crossed +  make_interval(secs := parameters.max_microtimestamp_change(p_pair_id, p_exchange_id)) >= crossed_books.next_uncrossed then
			return query select * from obanalytics.merge_episodes(crossed_books.first_crossed, crossed_books.next_uncrossed, p_pair_id, p_exchange_id);
		else
			raise exception 'Interval from % to % exceeds maximum allowed interval %', crossed_books.first_crossed, crossed_books.next_uncrossed, make_interval(secs := parameters.max_microtimestamp_change());
		end if;
	end loop;
	raise debug 'merge_crossed_books() exec time: %', clock_timestamp() - v_execution_start_time;	
end;	

$$;


ALTER FUNCTION obanalytics.merge_crossed_books(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer) OWNER TO "ob-analytics";

--
-- Name: FUNCTION merge_crossed_books(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer); Type: COMMENT; Schema: obanalytics; Owner: ob-analytics
--

COMMENT ON FUNCTION obanalytics.merge_crossed_books(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer) IS 'Merges episode(s) which produce crossed book into the next one which does not ';


--
-- Name: merge_episodes(timestamp with time zone, timestamp with time zone, integer, integer); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.merge_episodes(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer) RETURNS SETOF obanalytics.level3
    LANGUAGE sql
    AS $$
with to_be_updated as (
	select coalesce(min(microtimestamp) filter (where next_microtimestamp = '-infinity') over (partition by order_id order by microtimestamp desc), 
					'infinity'::timestamptz) as next_death,
			first_value(microtimestamp) over (partition by order_id order by microtimestamp desc) as last_seen,
			microtimestamp, order_id, event_no 
	from obanalytics.level3
	where pair_id = p_pair_id
	  and exchange_id = p_exchange_id
	  and microtimestamp >= p_start_time
	  and microtimestamp < p_end_time
)
update obanalytics.level3
    set microtimestamp = case when next_death < p_end_time 
							         and next_death < last_seen -- the order is resurrected after next_death.
									 							-- Bitfinex does that and we can use next_death for Bitfinex because all matches are single-sided
																-- In case of Bitstamp we would have to move both sides of the match - much more difficult to do ...
									then next_death
							   else p_end_time 
							   end,
		next_microtimestamp = case when level3.next_microtimestamp > '-infinity'and level3.next_microtimestamp <= next_death 
											and isfinite(level3.next_microtimestamp) and isfinite(next_death) 
											and next_death < last_seen -- the order is resurrected after next_death. Bitfinex does that
										then next_death
									when level3.next_microtimestamp > '-infinity'and level3.next_microtimestamp < p_end_time
										then p_end_time
									else level3.next_microtimestamp 
									end
from to_be_updated 
/*select case when next_death < p_end_time 
			then next_death
		   else p_end_time 
	    end as microtimestamp,
		level3.order_id,
		level3.event_no,
		level3.side,
		level3.price,
		level3.amount,
		level3.fill,
		case when level3.next_microtimestamp > '-infinity'and level3.next_microtimestamp <= next_death and isfinite(level3.next_microtimestamp)
				then next_death
			  when level3.next_microtimestamp > '-infinity'and level3.next_microtimestamp < p_end_time
			  	then p_end_time
			  else level3.next_microtimestamp 
			  end as next_microtimestamp,
	     level3.next_event_no,
		 level3.pair_id,
		 level3.exchange_id,
		 level3.local_timestamp,
		 level3.price_microtimestamp,
		 level3.price_event_no,
		 level3.exchange_microtimestamp,
		 level3.is_maker,
		 level3.is_crossed
from obanalytics.level3, to_be_updated 
*/
where level3.pair_id = p_pair_id
  and level3.exchange_id = p_exchange_id
  and level3.microtimestamp >= p_start_time
  and level3.microtimestamp < p_end_time
  and level3.microtimestamp = to_be_updated.microtimestamp
  and level3.order_id = to_be_updated.order_id
  and level3.event_no = to_be_updated.event_no
returning level3.*;  

$$;


ALTER FUNCTION obanalytics.merge_episodes(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer) OWNER TO "ob-analytics";

--
-- Name: order_book(timestamp with time zone, integer, integer, boolean, boolean, boolean, character); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.order_book(p_ts timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_only_makers boolean, p_before boolean, p_check_takers boolean DEFAULT false, p_side character DEFAULT NULL::bpchar) RETURNS TABLE(ts timestamp with time zone, ob obanalytics.level3[])
    LANGUAGE sql STABLE
    AS $$
	with orders as (
			select microtimestamp, order_id, event_no, side, price, amount, fill, next_microtimestamp, next_event_no, pair_id, exchange_id, local_timestamp,
					price_microtimestamp, price_event_no, exchange_microtimestamp, 
					coalesce(
						case side 
							when 'b' then price <= min(price) filter (where side = 's' and amount > 0 ) over (order by price_microtimestamp, microtimestamp)
							when 's' then price >= max(price) filter (where side = 'b' and amount > 0 ) over (order by price_microtimestamp, microtimestamp)
						end,
					true )	-- if there are only 'b' or 's' orders in the order book at some moment in time, then all of them are makers
					as is_maker,
					coalesce(
						case side 
							when 'b' then price > min(price) filter (where side = 's' and amount > 0 ) over (order by price_microtimestamp desc, microtimestamp desc)
							when 's' then price < max(price) filter (where side = 'b' and amount > 0 ) over (order by price_microtimestamp desc, microtimestamp desc)
						end,
					false )	-- if there are only 'b' or 's' orders in the order book at some moment in time, then all of them are not crossed
					as is_crossed
			from obanalytics.level3 
			where microtimestamp >= ( select max(era) as s
				 					   from obanalytics.level3_eras 
				 					   where era <= p_ts 
				    					 and pair_id = p_pair_id 
				   						 and exchange_id = p_exchange_id ) 
			  and case when p_before then  microtimestamp < p_ts and next_microtimestamp >= p_ts 
						when not p_before then microtimestamp <= p_ts and next_microtimestamp > p_ts 
		  	      end
			  and case when p_side is null then true else side =p_side end
			  and pair_id = p_pair_id
			  and exchange_id = p_exchange_id		
		)
	select (select max(microtimestamp) from orders ) as ts,
			array_agg(orders::obanalytics.level3 order by price, microtimestamp, order_id, event_no) 	
				  -- order by must be the same as in obanalytics._order_book_after_episode(). Change both!
    from orders
	where is_maker OR NOT p_only_makers
	  and (not p_check_takers or (not is_maker and obanalytics._is_valid_taker_event(microtimestamp, order_id, event_no, pair_id, exchange_id, next_microtimestamp)));

$$;


ALTER FUNCTION obanalytics.order_book(p_ts timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_only_makers boolean, p_before boolean, p_check_takers boolean, p_side character) OWNER TO "ob-analytics";

--
-- Name: order_book_by_episode(timestamp with time zone, timestamp with time zone, integer, integer, boolean); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.order_book_by_episode(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_check_takers boolean DEFAULT true) RETURNS TABLE(ts timestamp with time zone, ob obanalytics.level3[])
    LANGUAGE sql STABLE
    AS $$

-- ARGUMENTS
--		p_start_time  - the start of the interval for the production of the order book snapshots
--		p_end_time	  - the end of the interval
--		p_pair_id	  - id of the pair for which order books will be calculated
--		p_exchange_id - id of the exchange where order book is calculated

-- DETAILS
-- 		An episode is a moment in time when the order book, derived from obanalytics's data is in consistent state. 
--		The state of the order book is consistent when:
--			(a) all events that happened simultaneously (i.e. having the same microtimestamp) are reflected in the order book
--			(b) both events that constitute a trade are reflected in the order book
-- 		This function processes the order book events sequentially and returns consistent snapshots of the order book between
--		p_start_time and p_end_time.
--		These consistent snapshots are then used to calculate spread, depth and depth.summary. Note that the consitent order book may still be crossed.
--		It is assumed that spread, depth and depth.summary will ignore the unprocessed agressors crossing the book. 
--		
with eras as (
	select era, next_era
	from (
		select era, coalesce(lead(era) over (order by era), 'infinity') as next_era
		from obanalytics.level3_eras
		where pair_id = p_pair_id
		  and exchange_id = p_exchange_id 
	) a
	where p_start_time < next_era 
	  and p_end_time >= era
)
select microtimestamp as ts, obanalytics.order_book_agg(episode, p_check_takers) over (partition by era order by microtimestamp)  as ob
from (
	select microtimestamp, array_agg(level3) as episode
	from obanalytics.level3
	where microtimestamp between p_start_time and p_end_time
	  and pair_id = p_pair_id
	  and exchange_id = p_exchange_id
	group by microtimestamp  
) a join eras on microtimestamp >= era and microtimestamp < next_era
order by era, ts

$$;


ALTER FUNCTION obanalytics.order_book_by_episode(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_check_takers boolean) OWNER TO "ob-analytics";

--
-- Name: propagate_microtimestamp_change(); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.propagate_microtimestamp_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$begin
	update bitstamp.live_orders
	set microtimestamp = new.microtimestamp
	where order_type = case new.side when 's' then 'sell'::bitstamp.direction
								when 'b' then 'buy'::bitstamp.direction
				  end
	  and microtimestamp = old.microtimestamp
	  and order_id = old.order_id
	  and event_no = old.event_no;
	return null;
end;	  
$$;


ALTER FUNCTION obanalytics.propagate_microtimestamp_change() OWNER TO "ob-analytics";

--
-- Name: qty_level3_fix_duplicate_order_events(integer, integer, timestamp with time zone); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.qty_level3_fix_duplicate_order_events(p_pair_id integer, p_exchange_id integer, p_ts_within_era timestamp with time zone) RETURNS SETOF obanalytics.level3
    LANGUAGE plpgsql
    AS $$

-- NOTE: This function fixes only the most obvious errors. The remaining errors need to be fixed manually!

declare
	v_era_start timestamptz;
	v_era_end timestamptz;
begin

	select era, level3 into strict v_era_start, v_era_end
	from obanalytics.level3_eras
	where p_ts_within_era between era and level3
	  and pair_id = p_pair_id
	  and exchange_id = p_exchange_id;

	
	return query
	with level3 as (
		select * 
		from obanalytics.level3 
		where microtimestamp between v_era_start and v_era_end
		  and pair_id = p_pair_id
		  and exchange_id = p_exchange_id
	),
	order_ids as (
		select distinct order_id
		from level3 o
		group by order_id, event_no
		having count(*) > 1
	)
	delete 	from obanalytics.level3 
	where microtimestamp between v_era_start and v_era_end
	  and pair_id = p_pair_id
	  and exchange_id = p_exchange_id
	  and event_no = 1
	  and next_microtimestamp = 'infinity'
	  and order_id in (select * from order_ids)
	returning level3.*;
	
end;
$$;


ALTER FUNCTION obanalytics.qty_level3_fix_duplicate_order_events(p_pair_id integer, p_exchange_id integer, p_ts_within_era timestamp with time zone) OWNER TO "ob-analytics";

--
-- Name: qty_level3_fix_eternals(integer, integer, timestamp with time zone); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.qty_level3_fix_eternals(p_pair_id integer, p_exchange_id integer, p_ts_within_era timestamp with time zone) RETURNS SETOF obanalytics.level3
    LANGUAGE plpgsql
    AS $$
declare
	v_era_start timestamptz;
	v_era_end timestamptz;
begin

	select era, level3 into strict v_era_start, v_era_end
	from obanalytics.level3_eras
	where p_ts_within_era between era and level3
	  and pair_id = p_pair_id
	  and exchange_id = p_exchange_id;

	return query
	with level3 as (
		select * 
		from obanalytics.level3 
		where microtimestamp between v_era_start and v_era_end
		  and pair_id = p_pair_id
		  and exchange_id = p_exchange_id
	),
	orphans as (
		select microtimestamp, order_id, event_no
		from level3 o 
		where event_no > 1
		  and not exists ( select * 
						  	from level3 i 
						  	where next_microtimestamp = o.microtimestamp 
						  	  and i.order_id = o.order_id 
						  	  and next_event_no = o.event_no ) -- orphan
	),
	reconnect_eternals as (	-- reconnect eternal events to the appropriate existing next
		update obanalytics.level3
		set next_microtimestamp = orphans.microtimestamp,
		    next_event_no = orphans.event_no
		from orphans
		where level3.microtimestamp between v_era_start and v_era_end
		  and pair_id = p_pair_id
		  and exchange_id = p_exchange_id
		  and next_microtimestamp = 'infinity'
		  and level3.event_no = orphans.event_no - 1
		  and level3.order_id = orphans.order_id
		returning level3.*
	)
	select *
	from reconnect_eternals
	order by order_id, event_no, microtimestamp;
end;
$$;


ALTER FUNCTION obanalytics.qty_level3_fix_eternals(p_pair_id integer, p_exchange_id integer, p_ts_within_era timestamp with time zone) OWNER TO "ob-analytics";

--
-- Name: qty_level3_fix_premature_deletes(integer, integer, timestamp with time zone); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.qty_level3_fix_premature_deletes(p_pair_id integer, p_exchange_id integer, p_ts_within_era timestamp with time zone) RETURNS SETOF obanalytics.level3
    LANGUAGE plpgsql
    AS $$
declare
	v_era_start timestamptz;
	v_era_end timestamptz;
begin

	select era, level3 into strict v_era_start, v_era_end
	from obanalytics.level3_eras
	where p_ts_within_era between era and level3
	  and pair_id = p_pair_id
	  and exchange_id = p_exchange_id;

	return query
	with level3 as (
		select * 
		from obanalytics.level3 
		where microtimestamp between v_era_start and v_era_end
		  and pair_id = p_pair_id
		  and exchange_id = p_exchange_id
	),
	generated_deletes as (	
		select microtimestamp as g_microtimestamp, order_id, event_no
		from level3 o
		where next_microtimestamp = '-infinity'
		  and local_timestamp is null -- order_delete events which were produced by us, not buy exchange
	),
	exchange_next as (
		select microtimestamp as e_microtimestamp, order_id, event_no, g_microtimestamp
		from level3 o join generated_deletes using (order_id, event_no)
		where local_timestamp is not null  -- next events which were produced by exchange, with the same order_id, event_no
		  and not exists (select * 
						  	from level3 i 
						  	where next_microtimestamp = o.microtimestamp 
						  	  and i.order_id = o.order_id 
						  	  and next_event_no = o.event_no ) -- orphan
	),
	reconnect_chain as (	-- reconnect event to exchange_deletes instead of generated_deletes
		update obanalytics.level3
		set next_microtimestamp = e_microtimestamp
		from exchange_next
		where microtimestamp between v_era_start and v_era_end
		  and pair_id = p_pair_id
		  and exchange_id = p_exchange_id
		  and next_microtimestamp = exchange_next.g_microtimestamp
		  and level3.order_id = exchange_next.order_id
		  and next_event_no = exchange_next.event_no
		returning level3.*
	)
	select *
	from reconnect_chain
	order by order_id, event_no, microtimestamp;
	
	return query 
	delete from obanalytics.level3 o 
	where  microtimestamp between v_era_start and v_era_end
	  and pair_id = p_pair_id
	  and exchange_id = p_exchange_id
	  and next_microtimestamp = '-infinity'
	  and local_timestamp is null  -- order_delete events which were produced by us
	  and not exists (select * 
					 	from obanalytics.level3 i 
						where	microtimestamp between v_era_start and v_era_end
	  					  and pair_id = p_pair_id
	  					  and exchange_id = p_exchange_id
					  	  and next_microtimestamp = o.microtimestamp 
						  and i.order_id = o.order_id 
						  and next_event_no = o.event_no ) -- orphan
	returning o.*;					  
end;
$$;


ALTER FUNCTION obanalytics.qty_level3_fix_premature_deletes(p_pair_id integer, p_exchange_id integer, p_ts_within_era timestamp with time zone) OWNER TO "ob-analytics";

--
-- Name: qty_level3_show_duplicate_order_events(integer, integer, timestamp with time zone); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.qty_level3_show_duplicate_order_events(p_pair_id integer, p_exchange_id integer, p_ts_within_era timestamp with time zone) RETURNS SETOF obanalytics.level3
    LANGUAGE plpgsql
    AS $$
declare
	v_era_start timestamptz;
	v_era_end timestamptz;
begin

	select era, level3 into strict v_era_start, v_era_end
	from obanalytics.level3_eras
	where p_ts_within_era between era and level3
	  and pair_id = p_pair_id
	  and exchange_id = p_exchange_id;

	return query
	with level3 as (
		select * 
		from obanalytics.level3 
		where microtimestamp between v_era_start and v_era_end
		  and pair_id = p_pair_id
		  and exchange_id = p_exchange_id
	),
	order_ids as (
		select distinct order_id
		from level3 o
		group by order_id, event_no
		having count(*) > 1
	)
	select *
	from level3
	where order_id in (select * from order_ids )
	order by order_id, event_no, microtimestamp;
	
end;
$$;


ALTER FUNCTION obanalytics.qty_level3_show_duplicate_order_events(p_pair_id integer, p_exchange_id integer, p_ts_within_era timestamp with time zone) OWNER TO "ob-analytics";

--
-- Name: qty_level3_show_invalid_chains(integer, integer, timestamp with time zone); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.qty_level3_show_invalid_chains(p_pair_id integer, p_exchange_id integer, p_ts_within_era timestamp with time zone) RETURNS SETOF obanalytics.level3
    LANGUAGE plpgsql
    AS $$
declare
	v_era_start timestamptz;
	v_era_end timestamptz;
begin

	select era, level3 into strict v_era_start, v_era_end
	from obanalytics.level3_eras
	where p_ts_within_era between era and level3
	  and pair_id = p_pair_id
	  and exchange_id = p_exchange_id;

	return query
	with level3 as (
		select * 
		from obanalytics.level3 
		where microtimestamp between v_era_start and v_era_end
		  and pair_id = p_pair_id
		  and exchange_id = p_exchange_id
	),
	order_ids as (
		select distinct order_id
		from level3 o
		where event_no > 1
		  and not exists (select * from level3 i where next_microtimestamp = o.microtimestamp and  i.order_id = o.order_id and next_event_no = o.event_no )
	)
	select *
	from level3
	where order_id in (select * from order_ids )
	order by order_id, event_no, microtimestamp;
	
end;
$$;


ALTER FUNCTION obanalytics.qty_level3_show_invalid_chains(p_pair_id integer, p_exchange_id integer, p_ts_within_era timestamp with time zone) OWNER TO "ob-analytics";

--
-- Name: save_exchange_microtimestamp(); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.save_exchange_microtimestamp() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ 
begin
	-- It is assumed that the first-ever value of microtimestamp column is set by an exchange.
	-- If it is changed for the first time, then save it to exchange_microtimestamp.
	if old.exchange_microtimestamp is null then
		if old.microtimestamp is distinct from new.microtimestamp then
			new.exchange_microtimestamp := old.microtimestamp;
		end if;
	end if;		
	return new;
end;
	

$$;


ALTER FUNCTION obanalytics.save_exchange_microtimestamp() OWNER TO "ob-analytics";

--
-- Name: spread_by_episode_fast(timestamp with time zone, timestamp with time zone, integer, integer, interval); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.spread_by_episode_fast(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_frequency interval DEFAULT NULL::interval) RETURNS SETOF obanalytics.level1
    LANGUAGE c
    AS '$libdir/libobadiah_db.so.1', 'spread_by_episode';


ALTER FUNCTION obanalytics.spread_by_episode_fast(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_frequency interval) OWNER TO "ob-analytics";

--
-- Name: spread_by_episode_slow(timestamp with time zone, timestamp with time zone, integer, integer, boolean, boolean); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.spread_by_episode_slow(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_only_different boolean DEFAULT true, p_with_order_book boolean DEFAULT false) RETURNS TABLE(best_bid_price numeric, best_bid_qty numeric, best_ask_price numeric, best_ask_qty numeric, microtimestamp timestamp with time zone, pair_id smallint, exchange_id smallint, order_book obanalytics.level3[])
    LANGUAGE sql STABLE
    AS $$
-- ARGUMENTS
--		p_start_time  - the start of the interval for the calculation of spreads
--		p_end_time	  - the end of the interval
--		p_pair_id	  - the pair for which spreads will be calculated
--		p_exchange_id - the exchange where spreads will be calculated for
--		p_only_different - whether to output a spread when it is different from the previous one
--		p_with_order_book - whether to output the order book which was used to calculate spread (slow, generates a lot of data!)

with spread as (
	select (obanalytics._spread_from_order_book(ts, ob)).*, case  when p_with_order_book then ob else null end as ob
	from obanalytics.order_book_by_episode(p_start_time, p_end_time, p_pair_id, p_exchange_id, p_check_takers := false)
)
select best_bid_price, best_bid_qty, best_ask_price, best_ask_qty, microtimestamp, pair_id, exchange_id, ob
from (
	select best_bid_price, best_bid_qty, best_ask_price, best_ask_qty, microtimestamp, pair_id, exchange_id, ob,
		    lag(best_bid_price) over w as p_best_bid_price, 
			lag(best_bid_qty) over w as p_best_bid_qty,
			lag(best_ask_price) over w as p_best_ask_price,
			lag(best_ask_qty) over w as p_best_ask_qty
	from spread
	window w as (order by microtimestamp)
) a
where microtimestamp is not null 
  and ( not p_only_different 
	   	 or best_bid_price is distinct from p_best_bid_price
	     or best_bid_qty is distinct from p_best_bid_qty
	     or best_ask_price is distinct from p_best_ask_price
	     or best_ask_qty is distinct from p_best_ask_qty
	   )
order by microtimestamp

$$;


ALTER FUNCTION obanalytics.spread_by_episode_slow(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_pair_id integer, p_exchange_id integer, p_only_different boolean, p_with_order_book boolean) OWNER TO "ob-analytics";

--
-- Name: summary(text, text, timestamp with time zone, timestamp with time zone); Type: FUNCTION; Schema: obanalytics; Owner: ob-analytics
--

CREATE FUNCTION obanalytics.summary(p_exchange text DEFAULT NULL::text, p_pair text DEFAULT NULL::text, p_start_time timestamp with time zone DEFAULT (now() - '02:00:00'::interval), p_end_time timestamp with time zone DEFAULT 'infinity'::timestamp with time zone) RETURNS TABLE(pair text, e_first text, e_last text, e_total bigint, e_per_sec numeric, t_first text, t_last text, t_total bigint, t_per_sec numeric, t_matched bigint, t_exchange bigint, exchange text, era text)
    LANGUAGE sql STABLE
    AS $$
		
with periods as (
	select exchange_id, pair_id, 
			case when p_starts < p_start_time then p_start_time else p_starts end as period_starts, 
			case when p_ends > p_end_time then p_end_time else p_ends end as period_ends, 	
			era
	from (
		select exchange_id, pair_id, era as p_starts, 
				coalesce(lead(era) over (partition by exchange_id, pair_id order by era) - '00:00:00.000001'::interval, 'infinity'::timestamptz) as p_ends, era
		from obanalytics.level3_eras
		where exchange_id in ( select exchange_id from obanalytics.exchanges where exchange = coalesce(lower(p_exchange), exchange) )
		  and pair_id in ( select pair_id from obanalytics.pairs where pair = coalesce(upper(p_pair), pair))
	) p 
	where p_ends >= p_start_time
   	  and p_starts <= p_end_time 
),
level3_base as (
	select * 
	from obanalytics.level3 
	where exchange_id in ( select exchange_id from obanalytics.exchanges where exchange = coalesce(lower(p_exchange), exchange))
	  and pair_id in ( select pair_id from obanalytics.pairs where pair = coalesce(upper(p_pair), pair))
	  and microtimestamp  between p_start_time and p_end_time
),
events as (		
	select exchange_id,
			pair_id,
			period_starts,
			period_ends,
			min(microtimestamp) filter (where microtimestamp between period_starts and period_ends) as e_first, 
			max(microtimestamp) filter (where microtimestamp between period_starts and period_ends) as e_last,
			count(*) filter (where microtimestamp between period_starts and period_ends) as e_total
	from periods join level3_base using (exchange_id, pair_id)
	where microtimestamp between period_starts and period_ends 	
	  
	group by exchange_id, pair_id, period_starts, period_ends
),
matches_base as (
	select *
	from obanalytics.matches
	where exchange_id in ( select exchange_id from obanalytics.exchanges where exchange = coalesce(lower(p_exchange), exchange))
	  and pair_id in ( select pair_id from obanalytics.pairs where pair = coalesce(upper(p_pair), pair))
	  and microtimestamp  between p_start_time and p_end_time
),
trades as (		
	select exchange_id,
			pair_id,
			period_starts,
			period_ends,
			min(microtimestamp) filter (where microtimestamp between period_starts and period_ends) as t_first, 
			max(microtimestamp) filter (where microtimestamp between period_starts and period_ends) as t_last,
			count(*) filter (where microtimestamp between period_starts and period_ends) as t_total,
			count(*) filter (where microtimestamp between period_starts and period_ends and (buy_order_id is not null or sell_order_id is not null )) as t_matched,
			count(*) filter (where microtimestamp between period_starts and period_ends and exchange_trade_id is not null) as t_exchange
	from periods join matches_base using (exchange_id, pair_id)
	where microtimestamp between period_starts and period_ends
	group by exchange_id, pair_id, period_starts, period_ends
)		
select pairs.pair, e_first::text, e_last::text, e_total, 
		case  when extract( epoch from e_last - e_first ) > 0 then round((e_total/extract( epoch from e_last - e_first ))::numeric,2)
	  		   else 0 
		end as e_per_sec,		
		t_first::text, t_last::text,
		t_total, 
		case  when extract( epoch from t_last - t_first ) > 0 then round((t_total/extract( epoch from t_last - t_first ))::numeric,2)
	  		   else 0 
		end as t_per_sec,		
		t_matched, t_exchange, exchanges.exchange, periods.era::text
from periods join obanalytics.pairs using (pair_id) join obanalytics.exchanges using (exchange_id) left join events using (exchange_id, pair_id, period_starts, period_ends)
		left join trades using (exchange_id, pair_id, period_starts, period_ends)
where e_first is not null							 
$$;


ALTER FUNCTION obanalytics.summary(p_exchange text, p_pair text, p_start_time timestamp with time zone, p_end_time timestamp with time zone) OWNER TO "ob-analytics";

--
-- Name: depth_change_agg(obanalytics.level3[]); Type: AGGREGATE; Schema: obanalytics; Owner: ob-analytics
--

CREATE AGGREGATE obanalytics.depth_change_agg(obanalytics.level3[]) (
    SFUNC = obanalytics._depth_change_sfunc,
    STYPE = obanalytics.pair_of_ob,
    FINALFUNC = obanalytics._depth_change
);


ALTER AGGREGATE obanalytics.depth_change_agg(obanalytics.level3[]) OWNER TO "ob-analytics";

--
-- Name: depth_summary_agg(obanalytics.level2_depth_record[], timestamp with time zone, integer, integer, integer, integer); Type: AGGREGATE; Schema: obanalytics; Owner: ob-analytics
--

CREATE AGGREGATE obanalytics.depth_summary_agg(obanalytics.level2_depth_record[], timestamp with time zone, integer, integer, integer, integer) (
    SFUNC = obanalytics._depth_summary_after_depth_change,
    STYPE = obanalytics.level2_depth_summary_internal_state,
    FINALFUNC = obanalytics._depth_summary
);


ALTER AGGREGATE obanalytics.depth_summary_agg(obanalytics.level2_depth_record[], timestamp with time zone, integer, integer, integer, integer) OWNER TO "ob-analytics";

--
-- Name: order_book_agg(obanalytics.level3[], boolean); Type: AGGREGATE; Schema: obanalytics; Owner: ob-analytics
--

CREATE AGGREGATE obanalytics.order_book_agg(event obanalytics.level3[], boolean) (
    SFUNC = obanalytics._order_book_after_episode,
    STYPE = obanalytics.level3[]
);


ALTER AGGREGATE obanalytics.order_book_agg(event obanalytics.level3[], boolean) OWNER TO "ob-analytics";

--
-- Name: restore_depth_agg(obanalytics.level2_depth_record[], timestamp with time zone, integer, integer); Type: AGGREGATE; Schema: obanalytics; Owner: ob-analytics
--

CREATE AGGREGATE obanalytics.restore_depth_agg(obanalytics.level2_depth_record[], timestamp with time zone, integer, integer) (
    SFUNC = obanalytics._depth_after_depth_change,
    STYPE = obanalytics.level2_depth_record[]
);


ALTER AGGREGATE obanalytics.restore_depth_agg(obanalytics.level2_depth_record[], timestamp with time zone, integer, integer) OWNER TO "ob-analytics";

--
-- Name: level3_bitfinex; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitfinex (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint NOT NULL,
    exchange_id smallint DEFAULT 1 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY LIST (pair_id);
ALTER TABLE ONLY obanalytics.level3 ATTACH PARTITION obanalytics.level3_bitfinex FOR VALUES IN ('1');


ALTER TABLE obanalytics.level3_bitfinex OWNER TO "ob-analytics";

--
-- Name: level3_bitfinex_btcusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitfinex_btcusd (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 1 NOT NULL,
    exchange_id smallint DEFAULT 1 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY LIST (side);
ALTER TABLE ONLY obanalytics.level3_bitfinex ATTACH PARTITION obanalytics.level3_bitfinex_btcusd FOR VALUES IN ('1');
ALTER TABLE ONLY obanalytics.level3_bitfinex_btcusd ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitfinex_btcusd OWNER TO "ob-analytics";

--
-- Name: level3_bitfinex_btcusd_b; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitfinex_btcusd_b (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) DEFAULT 'b'::bpchar NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 1 NOT NULL,
    exchange_id smallint DEFAULT 1 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level3_bitfinex_btcusd ATTACH PARTITION obanalytics.level3_bitfinex_btcusd_b FOR VALUES IN ('b');
ALTER TABLE ONLY obanalytics.level3_bitfinex_btcusd_b ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitfinex_btcusd_b OWNER TO "ob-analytics";

--
-- Name: level3_bitfinex_btcusd_s; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitfinex_btcusd_s (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) DEFAULT 's'::bpchar NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 1 NOT NULL,
    exchange_id smallint DEFAULT 1 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level3_bitfinex_btcusd ATTACH PARTITION obanalytics.level3_bitfinex_btcusd_s FOR VALUES IN ('s');
ALTER TABLE ONLY obanalytics.level3_bitfinex_btcusd_s ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitfinex_btcusd_s OWNER TO "ob-analytics";

--
-- Name: level3_bitfinex_ltcusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitfinex_ltcusd (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 2 NOT NULL,
    exchange_id smallint DEFAULT 1 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY LIST (side);
ALTER TABLE ONLY obanalytics.level3_bitfinex ATTACH PARTITION obanalytics.level3_bitfinex_ltcusd FOR VALUES IN ('2');
ALTER TABLE ONLY obanalytics.level3_bitfinex_ltcusd ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitfinex_ltcusd OWNER TO "ob-analytics";

--
-- Name: level3_bitfinex_ltcusd_b; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitfinex_ltcusd_b (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) DEFAULT 'b'::bpchar NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 2 NOT NULL,
    exchange_id smallint DEFAULT 1 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level3_bitfinex_ltcusd ATTACH PARTITION obanalytics.level3_bitfinex_ltcusd_b FOR VALUES IN ('b');
ALTER TABLE ONLY obanalytics.level3_bitfinex_ltcusd_b ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitfinex_ltcusd_b OWNER TO "ob-analytics";

--
-- Name: level3_bitfinex_ltcusd_s; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitfinex_ltcusd_s (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) DEFAULT 's'::bpchar NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 2 NOT NULL,
    exchange_id smallint DEFAULT 1 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level3_bitfinex_ltcusd ATTACH PARTITION obanalytics.level3_bitfinex_ltcusd_s FOR VALUES IN ('s');
ALTER TABLE ONLY obanalytics.level3_bitfinex_ltcusd_s ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitfinex_ltcusd_s OWNER TO "ob-analytics";

--
-- Name: level3_bitfinex_ethusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitfinex_ethusd (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 3 NOT NULL,
    exchange_id smallint DEFAULT 1 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY LIST (side);
ALTER TABLE ONLY obanalytics.level3_bitfinex ATTACH PARTITION obanalytics.level3_bitfinex_ethusd FOR VALUES IN ('3');
ALTER TABLE ONLY obanalytics.level3_bitfinex_ethusd ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitfinex_ethusd OWNER TO "ob-analytics";

--
-- Name: level3_bitfinex_ethusd_b; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitfinex_ethusd_b (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) DEFAULT 'b'::bpchar NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 3 NOT NULL,
    exchange_id smallint DEFAULT 1 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level3_bitfinex_ethusd ATTACH PARTITION obanalytics.level3_bitfinex_ethusd_b FOR VALUES IN ('b');
ALTER TABLE ONLY obanalytics.level3_bitfinex_ethusd_b ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitfinex_ethusd_b OWNER TO "ob-analytics";

--
-- Name: level3_bitfinex_ethusd_s; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitfinex_ethusd_s (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) DEFAULT 's'::bpchar NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 3 NOT NULL,
    exchange_id smallint DEFAULT 1 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level3_bitfinex_ethusd ATTACH PARTITION obanalytics.level3_bitfinex_ethusd_s FOR VALUES IN ('s');
ALTER TABLE ONLY obanalytics.level3_bitfinex_ethusd_s ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitfinex_ethusd_s OWNER TO "ob-analytics";

--
-- Name: level3_bitfinex_xrpusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitfinex_xrpusd (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 4 NOT NULL,
    exchange_id smallint DEFAULT 1 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY LIST (side);
ALTER TABLE ONLY obanalytics.level3_bitfinex ATTACH PARTITION obanalytics.level3_bitfinex_xrpusd FOR VALUES IN ('4');


ALTER TABLE obanalytics.level3_bitfinex_xrpusd OWNER TO "ob-analytics";

--
-- Name: level3_bitfinex_xrpusd_b; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitfinex_xrpusd_b (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) DEFAULT 'b'::bpchar NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 4 NOT NULL,
    exchange_id smallint DEFAULT 1 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level3_bitfinex_xrpusd ATTACH PARTITION obanalytics.level3_bitfinex_xrpusd_b FOR VALUES IN ('b');


ALTER TABLE obanalytics.level3_bitfinex_xrpusd_b OWNER TO "ob-analytics";

--
-- Name: level3_bitfinex_xrpusd_s; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitfinex_xrpusd_s (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) DEFAULT 's'::bpchar NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 4 NOT NULL,
    exchange_id smallint DEFAULT 1 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level3_bitfinex_xrpusd ATTACH PARTITION obanalytics.level3_bitfinex_xrpusd_s FOR VALUES IN ('s');


ALTER TABLE obanalytics.level3_bitfinex_xrpusd_s OWNER TO "ob-analytics";

--
-- Name: level3_bitstamp; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitstamp (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY LIST (pair_id);
ALTER TABLE ONLY obanalytics.level3 ATTACH PARTITION obanalytics.level3_bitstamp FOR VALUES IN ('2');


ALTER TABLE obanalytics.level3_bitstamp OWNER TO "ob-analytics";

--
-- Name: level3_bitstamp_btcusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitstamp_btcusd (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 1 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY LIST (side);
ALTER TABLE ONLY obanalytics.level3_bitstamp ATTACH PARTITION obanalytics.level3_bitstamp_btcusd FOR VALUES IN ('1');
ALTER TABLE ONLY obanalytics.level3_bitstamp_btcusd ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitstamp_btcusd OWNER TO "ob-analytics";

--
-- Name: level3_bitstamp_btcusd_b; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitstamp_btcusd_b (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) DEFAULT 'b'::bpchar NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 1 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level3_bitstamp_btcusd ATTACH PARTITION obanalytics.level3_bitstamp_btcusd_b FOR VALUES IN ('b');
ALTER TABLE ONLY obanalytics.level3_bitstamp_btcusd_b ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitstamp_btcusd_b OWNER TO "ob-analytics";

--
-- Name: level3_bitstamp_btcusd_s; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitstamp_btcusd_s (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) DEFAULT 's'::bpchar NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 1 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level3_bitstamp_btcusd ATTACH PARTITION obanalytics.level3_bitstamp_btcusd_s FOR VALUES IN ('s');
ALTER TABLE ONLY obanalytics.level3_bitstamp_btcusd_s ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitstamp_btcusd_s OWNER TO "ob-analytics";

--
-- Name: level3_bitstamp_ltcusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitstamp_ltcusd (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 2 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY LIST (side);
ALTER TABLE ONLY obanalytics.level3_bitstamp ATTACH PARTITION obanalytics.level3_bitstamp_ltcusd FOR VALUES IN ('2');
ALTER TABLE ONLY obanalytics.level3_bitstamp_ltcusd ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitstamp_ltcusd OWNER TO "ob-analytics";

--
-- Name: level3_bitstamp_ltcusd_b; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitstamp_ltcusd_b (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) DEFAULT 'b'::bpchar NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 2 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level3_bitstamp_ltcusd ATTACH PARTITION obanalytics.level3_bitstamp_ltcusd_b FOR VALUES IN ('b');
ALTER TABLE ONLY obanalytics.level3_bitstamp_ltcusd_b ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitstamp_ltcusd_b OWNER TO "ob-analytics";

--
-- Name: level3_bitstamp_ltcusd_s; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitstamp_ltcusd_s (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) DEFAULT 's'::bpchar NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 2 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level3_bitstamp_ltcusd ATTACH PARTITION obanalytics.level3_bitstamp_ltcusd_s FOR VALUES IN ('s');
ALTER TABLE ONLY obanalytics.level3_bitstamp_ltcusd_s ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitstamp_ltcusd_s OWNER TO "ob-analytics";

--
-- Name: level3_bitstamp_ethusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitstamp_ethusd (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 3 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY LIST (side);
ALTER TABLE ONLY obanalytics.level3_bitstamp ATTACH PARTITION obanalytics.level3_bitstamp_ethusd FOR VALUES IN ('3');
ALTER TABLE ONLY obanalytics.level3_bitstamp_ethusd ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitstamp_ethusd OWNER TO "ob-analytics";

--
-- Name: level3_bitstamp_ethusd_b; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitstamp_ethusd_b (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) DEFAULT 'b'::bpchar NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 3 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level3_bitstamp_ethusd ATTACH PARTITION obanalytics.level3_bitstamp_ethusd_b FOR VALUES IN ('b');
ALTER TABLE ONLY obanalytics.level3_bitstamp_ethusd_b ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitstamp_ethusd_b OWNER TO "ob-analytics";

--
-- Name: level3_bitstamp_ethusd_s; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitstamp_ethusd_s (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) DEFAULT 's'::bpchar NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 3 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level3_bitstamp_ethusd ATTACH PARTITION obanalytics.level3_bitstamp_ethusd_s FOR VALUES IN ('s');
ALTER TABLE ONLY obanalytics.level3_bitstamp_ethusd_s ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitstamp_ethusd_s OWNER TO "ob-analytics";

--
-- Name: level3_bitstamp_xrpusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitstamp_xrpusd (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 4 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY LIST (side);
ALTER TABLE ONLY obanalytics.level3_bitstamp ATTACH PARTITION obanalytics.level3_bitstamp_xrpusd FOR VALUES IN ('4');
ALTER TABLE ONLY obanalytics.level3_bitstamp_xrpusd ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitstamp_xrpusd OWNER TO "ob-analytics";

--
-- Name: level3_bitstamp_xrpusd_b; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitstamp_xrpusd_b (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) DEFAULT 'b'::bpchar NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 4 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level3_bitstamp_xrpusd ATTACH PARTITION obanalytics.level3_bitstamp_xrpusd_b FOR VALUES IN ('b');
ALTER TABLE ONLY obanalytics.level3_bitstamp_xrpusd_b ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitstamp_xrpusd_b OWNER TO "ob-analytics";

--
-- Name: level3_bitstamp_xrpusd_s; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitstamp_xrpusd_s (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) DEFAULT 's'::bpchar NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 4 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level3_bitstamp_xrpusd ATTACH PARTITION obanalytics.level3_bitstamp_xrpusd_s FOR VALUES IN ('s');
ALTER TABLE ONLY obanalytics.level3_bitstamp_xrpusd_s ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitstamp_xrpusd_s OWNER TO "ob-analytics";

--
-- Name: level3_bitstamp_bchusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitstamp_bchusd (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 5 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY LIST (side);
ALTER TABLE ONLY obanalytics.level3_bitstamp ATTACH PARTITION obanalytics.level3_bitstamp_bchusd FOR VALUES IN ('5');
ALTER TABLE ONLY obanalytics.level3_bitstamp_bchusd ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitstamp_bchusd OWNER TO "ob-analytics";

--
-- Name: level3_bitstamp_bchusd_b; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitstamp_bchusd_b (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) DEFAULT 'b'::bpchar NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 5 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level3_bitstamp_bchusd ATTACH PARTITION obanalytics.level3_bitstamp_bchusd_b FOR VALUES IN ('b');
ALTER TABLE ONLY obanalytics.level3_bitstamp_bchusd_b ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitstamp_bchusd_b OWNER TO "ob-analytics";

--
-- Name: level3_bitstamp_bchusd_s; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitstamp_bchusd_s (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) DEFAULT 's'::bpchar NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 5 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level3_bitstamp_bchusd ATTACH PARTITION obanalytics.level3_bitstamp_bchusd_s FOR VALUES IN ('s');
ALTER TABLE ONLY obanalytics.level3_bitstamp_bchusd_s ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitstamp_bchusd_s OWNER TO "ob-analytics";

--
-- Name: level3_bitstamp_btceur; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitstamp_btceur (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 6 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY LIST (side);
ALTER TABLE ONLY obanalytics.level3_bitstamp ATTACH PARTITION obanalytics.level3_bitstamp_btceur FOR VALUES IN ('6');
ALTER TABLE ONLY obanalytics.level3_bitstamp_btceur ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitstamp_btceur OWNER TO "ob-analytics";

--
-- Name: level3_bitstamp_btceur_b; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitstamp_btceur_b (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) DEFAULT 'b'::bpchar NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 6 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level3_bitstamp_btceur ATTACH PARTITION obanalytics.level3_bitstamp_btceur_b FOR VALUES IN ('b');
ALTER TABLE ONLY obanalytics.level3_bitstamp_btceur_b ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitstamp_btceur_b OWNER TO "ob-analytics";

--
-- Name: level3_bitstamp_btceur_s; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_bitstamp_btceur_s (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) DEFAULT 's'::bpchar NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 6 NOT NULL,
    exchange_id smallint DEFAULT 2 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level3_bitstamp_btceur ATTACH PARTITION obanalytics.level3_bitstamp_btceur_s FOR VALUES IN ('s');
ALTER TABLE ONLY obanalytics.level3_bitstamp_btceur_s ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_bitstamp_btceur_s OWNER TO "ob-analytics";

--
-- Name: level3_moex; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_moex (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint NOT NULL,
    exchange_id smallint DEFAULT 4 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY LIST (pair_id);
ALTER TABLE ONLY obanalytics.level3 ATTACH PARTITION obanalytics.level3_moex FOR VALUES IN ('4');


ALTER TABLE obanalytics.level3_moex OWNER TO "ob-analytics";

--
-- Name: level3_moex_sberrub; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_moex_sberrub (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 8 NOT NULL,
    exchange_id smallint DEFAULT 4 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY LIST (side);
ALTER TABLE ONLY obanalytics.level3_moex ATTACH PARTITION obanalytics.level3_moex_sberrub FOR VALUES IN ('8');
ALTER TABLE ONLY obanalytics.level3_moex_sberrub ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_moex_sberrub OWNER TO "ob-analytics";

--
-- Name: level3_moex_sberrub_b; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_moex_sberrub_b (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) DEFAULT 'b'::bpchar NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 8 NOT NULL,
    exchange_id smallint DEFAULT 4 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level3_moex_sberrub ATTACH PARTITION obanalytics.level3_moex_sberrub_b FOR VALUES IN ('b');


ALTER TABLE obanalytics.level3_moex_sberrub_b OWNER TO "ob-analytics";

--
-- Name: level3_moex_sberrub_s; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_moex_sberrub_s (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) DEFAULT 's'::bpchar NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 8 NOT NULL,
    exchange_id smallint DEFAULT 4 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level3_moex_sberrub ATTACH PARTITION obanalytics.level3_moex_sberrub_s FOR VALUES IN ('s');
ALTER TABLE ONLY obanalytics.level3_moex_sberrub_s ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_moex_sberrub_s OWNER TO "ob-analytics";

--
-- Name: level3_moex_vtbrrub; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_moex_vtbrrub (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 9 NOT NULL,
    exchange_id smallint DEFAULT 4 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY LIST (side);
ALTER TABLE ONLY obanalytics.level3_moex ATTACH PARTITION obanalytics.level3_moex_vtbrrub FOR VALUES IN ('9');
ALTER TABLE ONLY obanalytics.level3_moex_vtbrrub ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_moex_vtbrrub OWNER TO "ob-analytics";

--
-- Name: level3_moex_vtbrrub_b; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_moex_vtbrrub_b (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) DEFAULT 'b'::bpchar NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 9 NOT NULL,
    exchange_id smallint DEFAULT 4 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level3_moex_vtbrrub ATTACH PARTITION obanalytics.level3_moex_vtbrrub_b FOR VALUES IN ('b');


ALTER TABLE obanalytics.level3_moex_vtbrrub_b OWNER TO "ob-analytics";

--
-- Name: level3_moex_vtbrrub_s; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_moex_vtbrrub_s (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) DEFAULT 's'::bpchar NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 9 NOT NULL,
    exchange_id smallint DEFAULT 4 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level3_moex_vtbrrub ATTACH PARTITION obanalytics.level3_moex_vtbrrub_s FOR VALUES IN ('s');
ALTER TABLE ONLY obanalytics.level3_moex_vtbrrub_s ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_moex_vtbrrub_s OWNER TO "ob-analytics";

--
-- Name: level3_moex_lkohrub; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_moex_lkohrub (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 10 NOT NULL,
    exchange_id smallint DEFAULT 4 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY LIST (side);
ALTER TABLE ONLY obanalytics.level3_moex ATTACH PARTITION obanalytics.level3_moex_lkohrub FOR VALUES IN ('10');
ALTER TABLE ONLY obanalytics.level3_moex_lkohrub ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_moex_lkohrub OWNER TO "ob-analytics";

--
-- Name: level3_moex_lkohrub_b; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_moex_lkohrub_b (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) DEFAULT 'b'::bpchar NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 10 NOT NULL,
    exchange_id smallint DEFAULT 4 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level3_moex_lkohrub ATTACH PARTITION obanalytics.level3_moex_lkohrub_b FOR VALUES IN ('b');


ALTER TABLE obanalytics.level3_moex_lkohrub_b OWNER TO "ob-analytics";

--
-- Name: level3_moex_lkohrub_s; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_moex_lkohrub_s (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) DEFAULT 's'::bpchar NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 10 NOT NULL,
    exchange_id smallint DEFAULT 4 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level3_moex_lkohrub ATTACH PARTITION obanalytics.level3_moex_lkohrub_s FOR VALUES IN ('s');
ALTER TABLE ONLY obanalytics.level3_moex_lkohrub_s ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_moex_lkohrub_s OWNER TO "ob-analytics";

--
-- Name: level3_moex_gazprub; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_moex_gazprub (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 11 NOT NULL,
    exchange_id smallint DEFAULT 4 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY LIST (side);
ALTER TABLE ONLY obanalytics.level3_moex ATTACH PARTITION obanalytics.level3_moex_gazprub FOR VALUES IN ('11');
ALTER TABLE ONLY obanalytics.level3_moex_gazprub ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_moex_gazprub OWNER TO "ob-analytics";

--
-- Name: level3_moex_gazprub_b; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_moex_gazprub_b (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) DEFAULT 'b'::bpchar NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 11 NOT NULL,
    exchange_id smallint DEFAULT 4 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level3_moex_gazprub ATTACH PARTITION obanalytics.level3_moex_gazprub_b FOR VALUES IN ('b');


ALTER TABLE obanalytics.level3_moex_gazprub_b OWNER TO "ob-analytics";

--
-- Name: level3_moex_gazprub_s; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.level3_moex_gazprub_s (
    microtimestamp timestamp with time zone NOT NULL,
    order_id bigint NOT NULL,
    event_no integer NOT NULL,
    side character(1) DEFAULT 's'::bpchar NOT NULL,
    price numeric NOT NULL,
    amount numeric NOT NULL,
    fill numeric,
    next_microtimestamp timestamp with time zone NOT NULL,
    next_event_no integer,
    pair_id smallint DEFAULT 11 NOT NULL,
    exchange_id smallint DEFAULT 4 NOT NULL,
    local_timestamp timestamp with time zone,
    price_microtimestamp timestamp with time zone NOT NULL,
    price_event_no integer,
    exchange_microtimestamp timestamp with time zone,
    is_maker boolean,
    is_crossed boolean,
    CONSTRAINT amount_is_not_negative CHECK ((amount >= (0)::numeric)),
    CONSTRAINT is_crossed_is_always_null CHECK ((is_crossed IS NULL)),
    CONSTRAINT is_maker_is_always_null CHECK ((is_maker IS NULL)),
    CONSTRAINT next_event_no CHECK ((((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone) AND (next_event_no IS NOT NULL)) OR ((NOT ((next_microtimestamp < 'infinity'::timestamp with time zone) AND (next_microtimestamp > '-infinity'::timestamp with time zone))) AND (next_event_no IS NULL)))),
    CONSTRAINT next_is_not_behind CHECK (((next_microtimestamp = '-infinity'::timestamp with time zone) OR (next_microtimestamp >= microtimestamp))),
    CONSTRAINT price_is_not_negative CHECK ((price >= (0)::numeric))
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.level3_moex_gazprub ATTACH PARTITION obanalytics.level3_moex_gazprub_s FOR VALUES IN ('s');
ALTER TABLE ONLY obanalytics.level3_moex_gazprub_s ALTER COLUMN microtimestamp SET STATISTICS 1000;


ALTER TABLE obanalytics.level3_moex_gazprub_s OWNER TO "ob-analytics";

--
-- Name: matches_bitfinex; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches_bitfinex (
    amount numeric NOT NULL,
    price numeric NOT NULL,
    side character(1) NOT NULL,
    microtimestamp timestamp with time zone NOT NULL,
    buy_order_id bigint,
    buy_event_no integer,
    sell_order_id bigint,
    sell_event_no integer,
    buy_match_rule smallint,
    sell_match_rule smallint,
    local_timestamp timestamp with time zone,
    exchange_id smallint DEFAULT 1 NOT NULL,
    pair_id smallint NOT NULL,
    exchange_side character(1),
    exchange_trade_id bigint,
    exchange_microtimestamp timestamp with time zone
)
PARTITION BY LIST (pair_id);
ALTER TABLE ONLY obanalytics.matches ATTACH PARTITION obanalytics.matches_bitfinex FOR VALUES IN ('1');


ALTER TABLE obanalytics.matches_bitfinex OWNER TO "ob-analytics";

--
-- Name: matches_bitfinex_btcusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches_bitfinex_btcusd (
    amount numeric NOT NULL,
    price numeric NOT NULL,
    side character(1) NOT NULL,
    microtimestamp timestamp with time zone NOT NULL,
    buy_order_id bigint,
    buy_event_no integer,
    sell_order_id bigint,
    sell_event_no integer,
    buy_match_rule smallint,
    sell_match_rule smallint,
    local_timestamp timestamp with time zone,
    exchange_id smallint DEFAULT 1 NOT NULL,
    pair_id smallint DEFAULT 1 NOT NULL,
    exchange_side character(1),
    exchange_trade_id bigint,
    exchange_microtimestamp timestamp with time zone
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.matches_bitfinex ATTACH PARTITION obanalytics.matches_bitfinex_btcusd FOR VALUES IN ('1');


ALTER TABLE obanalytics.matches_bitfinex_btcusd OWNER TO "ob-analytics";

--
-- Name: matches_bitfinex_ltcusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches_bitfinex_ltcusd (
    amount numeric NOT NULL,
    price numeric NOT NULL,
    side character(1) NOT NULL,
    microtimestamp timestamp with time zone NOT NULL,
    buy_order_id bigint,
    buy_event_no integer,
    sell_order_id bigint,
    sell_event_no integer,
    buy_match_rule smallint,
    sell_match_rule smallint,
    local_timestamp timestamp with time zone,
    exchange_id smallint DEFAULT 1 NOT NULL,
    pair_id smallint DEFAULT 2 NOT NULL,
    exchange_side character(1),
    exchange_trade_id bigint,
    exchange_microtimestamp timestamp with time zone
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.matches_bitfinex ATTACH PARTITION obanalytics.matches_bitfinex_ltcusd FOR VALUES IN ('2');


ALTER TABLE obanalytics.matches_bitfinex_ltcusd OWNER TO "ob-analytics";

--
-- Name: matches_bitfinex_ethusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches_bitfinex_ethusd (
    amount numeric NOT NULL,
    price numeric NOT NULL,
    side character(1) NOT NULL,
    microtimestamp timestamp with time zone NOT NULL,
    buy_order_id bigint,
    buy_event_no integer,
    sell_order_id bigint,
    sell_event_no integer,
    buy_match_rule smallint,
    sell_match_rule smallint,
    local_timestamp timestamp with time zone,
    exchange_id smallint DEFAULT 1 NOT NULL,
    pair_id smallint DEFAULT 3 NOT NULL,
    exchange_side character(1),
    exchange_trade_id bigint,
    exchange_microtimestamp timestamp with time zone
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.matches_bitfinex ATTACH PARTITION obanalytics.matches_bitfinex_ethusd FOR VALUES IN ('3');


ALTER TABLE obanalytics.matches_bitfinex_ethusd OWNER TO "ob-analytics";

--
-- Name: matches_bitfinex_xrpusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches_bitfinex_xrpusd (
    amount numeric NOT NULL,
    price numeric NOT NULL,
    side character(1) NOT NULL,
    microtimestamp timestamp with time zone NOT NULL,
    buy_order_id bigint,
    buy_event_no integer,
    sell_order_id bigint,
    sell_event_no integer,
    buy_match_rule smallint,
    sell_match_rule smallint,
    local_timestamp timestamp with time zone,
    exchange_id smallint DEFAULT 1 NOT NULL,
    pair_id smallint DEFAULT 4 NOT NULL,
    exchange_side character(1),
    exchange_trade_id bigint,
    exchange_microtimestamp timestamp with time zone
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.matches_bitfinex ATTACH PARTITION obanalytics.matches_bitfinex_xrpusd FOR VALUES IN ('4');


ALTER TABLE obanalytics.matches_bitfinex_xrpusd OWNER TO "ob-analytics";

--
-- Name: matches_bitstamp; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches_bitstamp (
    amount numeric NOT NULL,
    price numeric NOT NULL,
    side character(1) NOT NULL,
    microtimestamp timestamp with time zone NOT NULL,
    buy_order_id bigint,
    buy_event_no integer,
    sell_order_id bigint,
    sell_event_no integer,
    buy_match_rule smallint,
    sell_match_rule smallint,
    local_timestamp timestamp with time zone,
    exchange_id smallint DEFAULT 2 NOT NULL,
    pair_id smallint NOT NULL,
    exchange_side character(1),
    exchange_trade_id bigint,
    exchange_microtimestamp timestamp with time zone
)
PARTITION BY LIST (pair_id);
ALTER TABLE ONLY obanalytics.matches ATTACH PARTITION obanalytics.matches_bitstamp FOR VALUES IN ('2');


ALTER TABLE obanalytics.matches_bitstamp OWNER TO "ob-analytics";

--
-- Name: matches_bitstamp_btcusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches_bitstamp_btcusd (
    amount numeric NOT NULL,
    price numeric NOT NULL,
    side character(1) NOT NULL,
    microtimestamp timestamp with time zone NOT NULL,
    buy_order_id bigint,
    buy_event_no integer,
    sell_order_id bigint,
    sell_event_no integer,
    buy_match_rule smallint,
    sell_match_rule smallint,
    local_timestamp timestamp with time zone,
    exchange_id smallint DEFAULT 2 NOT NULL,
    pair_id smallint DEFAULT 1 NOT NULL,
    exchange_side character(1),
    exchange_trade_id bigint,
    exchange_microtimestamp timestamp with time zone
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.matches_bitstamp ATTACH PARTITION obanalytics.matches_bitstamp_btcusd FOR VALUES IN ('1');


ALTER TABLE obanalytics.matches_bitstamp_btcusd OWNER TO "ob-analytics";

--
-- Name: matches_bitstamp_ltcusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches_bitstamp_ltcusd (
    amount numeric NOT NULL,
    price numeric NOT NULL,
    side character(1) NOT NULL,
    microtimestamp timestamp with time zone NOT NULL,
    buy_order_id bigint,
    buy_event_no integer,
    sell_order_id bigint,
    sell_event_no integer,
    buy_match_rule smallint,
    sell_match_rule smallint,
    local_timestamp timestamp with time zone,
    exchange_id smallint DEFAULT 2 NOT NULL,
    pair_id smallint DEFAULT 2 NOT NULL,
    exchange_side character(1),
    exchange_trade_id bigint,
    exchange_microtimestamp timestamp with time zone
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.matches_bitstamp ATTACH PARTITION obanalytics.matches_bitstamp_ltcusd FOR VALUES IN ('2');


ALTER TABLE obanalytics.matches_bitstamp_ltcusd OWNER TO "ob-analytics";

--
-- Name: matches_bitstamp_ethusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches_bitstamp_ethusd (
    amount numeric NOT NULL,
    price numeric NOT NULL,
    side character(1) NOT NULL,
    microtimestamp timestamp with time zone NOT NULL,
    buy_order_id bigint,
    buy_event_no integer,
    sell_order_id bigint,
    sell_event_no integer,
    buy_match_rule smallint,
    sell_match_rule smallint,
    local_timestamp timestamp with time zone,
    exchange_id smallint DEFAULT 2 NOT NULL,
    pair_id smallint DEFAULT 3 NOT NULL,
    exchange_side character(1),
    exchange_trade_id bigint,
    exchange_microtimestamp timestamp with time zone
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.matches_bitstamp ATTACH PARTITION obanalytics.matches_bitstamp_ethusd FOR VALUES IN ('3');


ALTER TABLE obanalytics.matches_bitstamp_ethusd OWNER TO "ob-analytics";

--
-- Name: matches_bitstamp_xrpusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches_bitstamp_xrpusd (
    amount numeric NOT NULL,
    price numeric NOT NULL,
    side character(1) NOT NULL,
    microtimestamp timestamp with time zone NOT NULL,
    buy_order_id bigint,
    buy_event_no integer,
    sell_order_id bigint,
    sell_event_no integer,
    buy_match_rule smallint,
    sell_match_rule smallint,
    local_timestamp timestamp with time zone,
    exchange_id smallint DEFAULT 2 NOT NULL,
    pair_id smallint DEFAULT 4 NOT NULL,
    exchange_side character(1),
    exchange_trade_id bigint,
    exchange_microtimestamp timestamp with time zone
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.matches_bitstamp ATTACH PARTITION obanalytics.matches_bitstamp_xrpusd FOR VALUES IN ('4');


ALTER TABLE obanalytics.matches_bitstamp_xrpusd OWNER TO "ob-analytics";

--
-- Name: matches_bitstamp_bchusd; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches_bitstamp_bchusd (
    amount numeric NOT NULL,
    price numeric NOT NULL,
    side character(1) NOT NULL,
    microtimestamp timestamp with time zone NOT NULL,
    buy_order_id bigint,
    buy_event_no integer,
    sell_order_id bigint,
    sell_event_no integer,
    buy_match_rule smallint,
    sell_match_rule smallint,
    local_timestamp timestamp with time zone,
    exchange_id smallint DEFAULT 2 NOT NULL,
    pair_id smallint DEFAULT 5 NOT NULL,
    exchange_side character(1),
    exchange_trade_id bigint,
    exchange_microtimestamp timestamp with time zone
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.matches_bitstamp ATTACH PARTITION obanalytics.matches_bitstamp_bchusd FOR VALUES IN ('5');


ALTER TABLE obanalytics.matches_bitstamp_bchusd OWNER TO "ob-analytics";

--
-- Name: matches_bitstamp_btceur; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches_bitstamp_btceur (
    amount numeric NOT NULL,
    price numeric NOT NULL,
    side character(1) NOT NULL,
    microtimestamp timestamp with time zone NOT NULL,
    buy_order_id bigint,
    buy_event_no integer,
    sell_order_id bigint,
    sell_event_no integer,
    buy_match_rule smallint,
    sell_match_rule smallint,
    local_timestamp timestamp with time zone,
    exchange_id smallint DEFAULT 2 NOT NULL,
    pair_id smallint DEFAULT 6 NOT NULL,
    exchange_side character(1),
    exchange_trade_id bigint,
    exchange_microtimestamp timestamp with time zone
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.matches_bitstamp ATTACH PARTITION obanalytics.matches_bitstamp_btceur FOR VALUES IN ('6');


ALTER TABLE obanalytics.matches_bitstamp_btceur OWNER TO "ob-analytics";

--
-- Name: matches_moex; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches_moex (
    amount numeric NOT NULL,
    price numeric NOT NULL,
    side character(1) NOT NULL,
    microtimestamp timestamp with time zone NOT NULL,
    buy_order_id bigint,
    buy_event_no integer,
    sell_order_id bigint,
    sell_event_no integer,
    buy_match_rule smallint,
    sell_match_rule smallint,
    local_timestamp timestamp with time zone,
    exchange_id smallint DEFAULT 4 NOT NULL,
    pair_id smallint NOT NULL,
    exchange_side character(1),
    exchange_trade_id bigint,
    exchange_microtimestamp timestamp with time zone
)
PARTITION BY LIST (pair_id);
ALTER TABLE ONLY obanalytics.matches ATTACH PARTITION obanalytics.matches_moex FOR VALUES IN ('4');


ALTER TABLE obanalytics.matches_moex OWNER TO "ob-analytics";

--
-- Name: matches_moex_sberrub; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches_moex_sberrub (
    amount numeric NOT NULL,
    price numeric NOT NULL,
    side character(1) NOT NULL,
    microtimestamp timestamp with time zone NOT NULL,
    buy_order_id bigint,
    buy_event_no integer,
    sell_order_id bigint,
    sell_event_no integer,
    buy_match_rule smallint,
    sell_match_rule smallint,
    local_timestamp timestamp with time zone,
    exchange_id smallint DEFAULT 4 NOT NULL,
    pair_id smallint DEFAULT 8 NOT NULL,
    exchange_side character(1),
    exchange_trade_id bigint,
    exchange_microtimestamp timestamp with time zone
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.matches_moex ATTACH PARTITION obanalytics.matches_moex_sberrub FOR VALUES IN ('8');


ALTER TABLE obanalytics.matches_moex_sberrub OWNER TO "ob-analytics";

--
-- Name: matches_moex_vtbrrub; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches_moex_vtbrrub (
    amount numeric NOT NULL,
    price numeric NOT NULL,
    side character(1) NOT NULL,
    microtimestamp timestamp with time zone NOT NULL,
    buy_order_id bigint,
    buy_event_no integer,
    sell_order_id bigint,
    sell_event_no integer,
    buy_match_rule smallint,
    sell_match_rule smallint,
    local_timestamp timestamp with time zone,
    exchange_id smallint DEFAULT 4 NOT NULL,
    pair_id smallint DEFAULT 9 NOT NULL,
    exchange_side character(1),
    exchange_trade_id bigint,
    exchange_microtimestamp timestamp with time zone
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.matches_moex ATTACH PARTITION obanalytics.matches_moex_vtbrrub FOR VALUES IN ('9');


ALTER TABLE obanalytics.matches_moex_vtbrrub OWNER TO "ob-analytics";

--
-- Name: matches_moex_lkohrub; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches_moex_lkohrub (
    amount numeric NOT NULL,
    price numeric NOT NULL,
    side character(1) NOT NULL,
    microtimestamp timestamp with time zone NOT NULL,
    buy_order_id bigint,
    buy_event_no integer,
    sell_order_id bigint,
    sell_event_no integer,
    buy_match_rule smallint,
    sell_match_rule smallint,
    local_timestamp timestamp with time zone,
    exchange_id smallint DEFAULT 4 NOT NULL,
    pair_id smallint DEFAULT 10 NOT NULL,
    exchange_side character(1),
    exchange_trade_id bigint,
    exchange_microtimestamp timestamp with time zone
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.matches_moex ATTACH PARTITION obanalytics.matches_moex_lkohrub FOR VALUES IN ('10');


ALTER TABLE obanalytics.matches_moex_lkohrub OWNER TO "ob-analytics";

--
-- Name: matches_moex_gazprub; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.matches_moex_gazprub (
    amount numeric NOT NULL,
    price numeric NOT NULL,
    side character(1) NOT NULL,
    microtimestamp timestamp with time zone NOT NULL,
    buy_order_id bigint,
    buy_event_no integer,
    sell_order_id bigint,
    sell_event_no integer,
    buy_match_rule smallint,
    sell_match_rule smallint,
    local_timestamp timestamp with time zone,
    exchange_id smallint DEFAULT 4 NOT NULL,
    pair_id smallint DEFAULT 11 NOT NULL,
    exchange_side character(1),
    exchange_trade_id bigint,
    exchange_microtimestamp timestamp with time zone
)
PARTITION BY RANGE (microtimestamp);
ALTER TABLE ONLY obanalytics.matches_moex ATTACH PARTITION obanalytics.matches_moex_gazprub FOR VALUES IN ('11');


ALTER TABLE obanalytics.matches_moex_gazprub OWNER TO "ob-analytics";

--
-- Name: exchanges; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.exchanges (
    exchange_id smallint NOT NULL,
    exchange text NOT NULL
);


ALTER TABLE obanalytics.exchanges OWNER TO "ob-analytics";

--
-- Name: level3_eras_bitfinex; Type: VIEW; Schema: obanalytics; Owner: ob-analytics
--

CREATE VIEW obanalytics.level3_eras_bitfinex AS
 SELECT level3_eras.era,
    level3_eras.pair_id,
    level3_eras.exchange_id
   FROM obanalytics.level3_eras
  WHERE (level3_eras.exchange_id = ( SELECT exchanges.exchange_id
           FROM obanalytics.exchanges
          WHERE (exchanges.exchange = 'bitfinex'::text)));


ALTER TABLE obanalytics.level3_eras_bitfinex OWNER TO "ob-analytics";

--
-- Name: level3_eras_bitstamp; Type: VIEW; Schema: obanalytics; Owner: ob-analytics
--

CREATE VIEW obanalytics.level3_eras_bitstamp AS
 SELECT level3_eras.era,
    level3_eras.pair_id,
    level3_eras.exchange_id
   FROM obanalytics.level3_eras
  WHERE (level3_eras.exchange_id = ( SELECT exchanges.exchange_id
           FROM obanalytics.exchanges
          WHERE (exchanges.exchange = 'bitstamp'::text)));


ALTER TABLE obanalytics.level3_eras_bitstamp OWNER TO "ob-analytics";

--
-- Name: pairs; Type: TABLE; Schema: obanalytics; Owner: ob-analytics
--

CREATE TABLE obanalytics.pairs (
    pair_id smallint NOT NULL,
    pair text NOT NULL,
    "R0" smallint,
    "P0" smallint,
    "P1" smallint,
    "P2" smallint,
    "P3" smallint,
    fmu smallint NOT NULL
);


ALTER TABLE obanalytics.pairs OWNER TO "ob-analytics";

--
-- Name: TABLE pairs; Type: COMMENT; Schema: obanalytics; Owner: ob-analytics
--

COMMENT ON TABLE obanalytics.pairs IS 'pair_id values are meaningful: they are used in the names of partition tables';


--
-- Name: COLUMN pairs."R0"; Type: COMMENT; Schema: obanalytics; Owner: ob-analytics
--

COMMENT ON COLUMN obanalytics.pairs."R0" IS '-log10 of Fractional Monetary Unit (i.e. 2 for 0.01 of USD or 8 for 0.00000001 of Bitcoin) for the secopnd currency in the pair (i.e. USD in BTCUSD). To be used for rounding of floating-point prices';


--
-- Name: COLUMN pairs.fmu; Type: COMMENT; Schema: obanalytics; Owner: ob-analytics
--

COMMENT ON COLUMN obanalytics.pairs.fmu IS '-log10 of Fractional Monetary Unit (i.e. 2 for 0.01 of USD or 8 for 0.00000001 of Bitcoin) for the first currency in the pair (i.e. BTC in BTCUSD). To be used for rounding of floating-point quantities ';


--
-- Name: exchanges exchanges_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.exchanges
    ADD CONSTRAINT exchanges_pkey PRIMARY KEY (exchange_id);


--
-- Name: exchanges exchanges_unique_exchange; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.exchanges
    ADD CONSTRAINT exchanges_unique_exchange UNIQUE (exchange);


--
-- Name: level3_bitstamp level3_bitstamp_pair_id_side_microtimestamp_order_id_event__key; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp
    ADD CONSTRAINT level3_bitstamp_pair_id_side_microtimestamp_order_id_event__key UNIQUE (pair_id, side, microtimestamp, order_id, event_no);


--
-- Name: level3_bitstamp_bchusd level3_bitstamp_bchusd_pair_id_side_microtimestamp_order_id_key; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_bchusd
    ADD CONSTRAINT level3_bitstamp_bchusd_pair_id_side_microtimestamp_order_id_key UNIQUE (pair_id, side, microtimestamp, order_id, event_no);


--
-- Name: level3_bitstamp_bchusd_b level3_bitstamp_bchusd_b_pair_id_side_microtimestamp_order__key; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_bchusd_b
    ADD CONSTRAINT level3_bitstamp_bchusd_b_pair_id_side_microtimestamp_order__key UNIQUE (pair_id, side, microtimestamp, order_id, event_no);


--
-- Name: level3_bitstamp_bchusd_s level3_bitstamp_bchusd_s_pair_id_side_microtimestamp_order__key; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_bchusd_s
    ADD CONSTRAINT level3_bitstamp_bchusd_s_pair_id_side_microtimestamp_order__key UNIQUE (pair_id, side, microtimestamp, order_id, event_no);


--
-- Name: level3_bitstamp_btceur level3_bitstamp_btceur_pair_id_side_microtimestamp_order_id_key; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_btceur
    ADD CONSTRAINT level3_bitstamp_btceur_pair_id_side_microtimestamp_order_id_key UNIQUE (pair_id, side, microtimestamp, order_id, event_no);


--
-- Name: level3_bitstamp_btceur_b level3_bitstamp_btceur_b_pair_id_side_microtimestamp_order__key; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_btceur_b
    ADD CONSTRAINT level3_bitstamp_btceur_b_pair_id_side_microtimestamp_order__key UNIQUE (pair_id, side, microtimestamp, order_id, event_no);


--
-- Name: level3_bitstamp_btceur_s level3_bitstamp_btceur_s_pair_id_side_microtimestamp_order__key; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_btceur_s
    ADD CONSTRAINT level3_bitstamp_btceur_s_pair_id_side_microtimestamp_order__key UNIQUE (pair_id, side, microtimestamp, order_id, event_no);


--
-- Name: level3_bitstamp_btcusd level3_bitstamp_btcusd_pair_id_side_microtimestamp_order_id_key; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_btcusd
    ADD CONSTRAINT level3_bitstamp_btcusd_pair_id_side_microtimestamp_order_id_key UNIQUE (pair_id, side, microtimestamp, order_id, event_no);


--
-- Name: level3_bitstamp_btcusd_b level3_bitstamp_btcusd_b_pair_id_side_microtimestamp_order__key; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_btcusd_b
    ADD CONSTRAINT level3_bitstamp_btcusd_b_pair_id_side_microtimestamp_order__key UNIQUE (pair_id, side, microtimestamp, order_id, event_no);


--
-- Name: level3_bitstamp_btcusd_s level3_bitstamp_btcusd_s_pair_id_side_microtimestamp_order__key; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_btcusd_s
    ADD CONSTRAINT level3_bitstamp_btcusd_s_pair_id_side_microtimestamp_order__key UNIQUE (pair_id, side, microtimestamp, order_id, event_no);


--
-- Name: level3_bitstamp_ethusd level3_bitstamp_ethusd_pair_id_side_microtimestamp_order_id_key; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_ethusd
    ADD CONSTRAINT level3_bitstamp_ethusd_pair_id_side_microtimestamp_order_id_key UNIQUE (pair_id, side, microtimestamp, order_id, event_no);


--
-- Name: level3_bitstamp_ethusd_b level3_bitstamp_ethusd_b_pair_id_side_microtimestamp_order__key; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_ethusd_b
    ADD CONSTRAINT level3_bitstamp_ethusd_b_pair_id_side_microtimestamp_order__key UNIQUE (pair_id, side, microtimestamp, order_id, event_no);


--
-- Name: level3_bitstamp_ethusd_s level3_bitstamp_ethusd_s_pair_id_side_microtimestamp_order__key; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_ethusd_s
    ADD CONSTRAINT level3_bitstamp_ethusd_s_pair_id_side_microtimestamp_order__key UNIQUE (pair_id, side, microtimestamp, order_id, event_no);


--
-- Name: level3_bitstamp_ltcusd level3_bitstamp_ltcusd_pair_id_side_microtimestamp_order_id_key; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_ltcusd
    ADD CONSTRAINT level3_bitstamp_ltcusd_pair_id_side_microtimestamp_order_id_key UNIQUE (pair_id, side, microtimestamp, order_id, event_no);


--
-- Name: level3_bitstamp_ltcusd_b level3_bitstamp_ltcusd_b_pair_id_side_microtimestamp_order__key; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_ltcusd_b
    ADD CONSTRAINT level3_bitstamp_ltcusd_b_pair_id_side_microtimestamp_order__key UNIQUE (pair_id, side, microtimestamp, order_id, event_no);


--
-- Name: level3_bitstamp_ltcusd_s level3_bitstamp_ltcusd_s_pair_id_side_microtimestamp_order__key; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_ltcusd_s
    ADD CONSTRAINT level3_bitstamp_ltcusd_s_pair_id_side_microtimestamp_order__key UNIQUE (pair_id, side, microtimestamp, order_id, event_no);


--
-- Name: level3_bitstamp_xrpusd level3_bitstamp_xrpusd_pair_id_side_microtimestamp_order_id_key; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_xrpusd
    ADD CONSTRAINT level3_bitstamp_xrpusd_pair_id_side_microtimestamp_order_id_key UNIQUE (pair_id, side, microtimestamp, order_id, event_no);


--
-- Name: level3_bitstamp_xrpusd_b level3_bitstamp_xrpusd_b_pair_id_side_microtimestamp_order__key; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_xrpusd_b
    ADD CONSTRAINT level3_bitstamp_xrpusd_b_pair_id_side_microtimestamp_order__key UNIQUE (pair_id, side, microtimestamp, order_id, event_no);


--
-- Name: level3_bitstamp_xrpusd_s level3_bitstamp_xrpusd_s_pair_id_side_microtimestamp_order__key; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_bitstamp_xrpusd_s
    ADD CONSTRAINT level3_bitstamp_xrpusd_s_pair_id_side_microtimestamp_order__key UNIQUE (pair_id, side, microtimestamp, order_id, event_no);


--
-- Name: level3_eras level3_eras_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.level3_eras
    ADD CONSTRAINT level3_eras_pkey PRIMARY KEY (era, pair_id, exchange_id);


--
-- Name: pairs pairs_pkey; Type: CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE ONLY obanalytics.pairs
    ADD CONSTRAINT pairs_pkey PRIMARY KEY (pair_id);


--
-- Name: level3_bitstamp_bchusd_b_pair_id_side_microtimestamp_order__key; Type: INDEX ATTACH; Schema: obanalytics; Owner: 
--

ALTER INDEX obanalytics.level3_bitstamp_bchusd_pair_id_side_microtimestamp_order_id_key ATTACH PARTITION obanalytics.level3_bitstamp_bchusd_b_pair_id_side_microtimestamp_order__key;


--
-- Name: level3_bitstamp_bchusd_pair_id_side_microtimestamp_order_id_key; Type: INDEX ATTACH; Schema: obanalytics; Owner: 
--

ALTER INDEX obanalytics.level3_bitstamp_pair_id_side_microtimestamp_order_id_event__key ATTACH PARTITION obanalytics.level3_bitstamp_bchusd_pair_id_side_microtimestamp_order_id_key;


--
-- Name: level3_bitstamp_bchusd_s_pair_id_side_microtimestamp_order__key; Type: INDEX ATTACH; Schema: obanalytics; Owner: 
--

ALTER INDEX obanalytics.level3_bitstamp_bchusd_pair_id_side_microtimestamp_order_id_key ATTACH PARTITION obanalytics.level3_bitstamp_bchusd_s_pair_id_side_microtimestamp_order__key;


--
-- Name: level3_bitstamp_btceur_b_pair_id_side_microtimestamp_order__key; Type: INDEX ATTACH; Schema: obanalytics; Owner: 
--

ALTER INDEX obanalytics.level3_bitstamp_btceur_pair_id_side_microtimestamp_order_id_key ATTACH PARTITION obanalytics.level3_bitstamp_btceur_b_pair_id_side_microtimestamp_order__key;


--
-- Name: level3_bitstamp_btceur_pair_id_side_microtimestamp_order_id_key; Type: INDEX ATTACH; Schema: obanalytics; Owner: 
--

ALTER INDEX obanalytics.level3_bitstamp_pair_id_side_microtimestamp_order_id_event__key ATTACH PARTITION obanalytics.level3_bitstamp_btceur_pair_id_side_microtimestamp_order_id_key;


--
-- Name: level3_bitstamp_btceur_s_pair_id_side_microtimestamp_order__key; Type: INDEX ATTACH; Schema: obanalytics; Owner: 
--

ALTER INDEX obanalytics.level3_bitstamp_btceur_pair_id_side_microtimestamp_order_id_key ATTACH PARTITION obanalytics.level3_bitstamp_btceur_s_pair_id_side_microtimestamp_order__key;


--
-- Name: level3_bitstamp_btcusd_b_pair_id_side_microtimestamp_order__key; Type: INDEX ATTACH; Schema: obanalytics; Owner: 
--

ALTER INDEX obanalytics.level3_bitstamp_btcusd_pair_id_side_microtimestamp_order_id_key ATTACH PARTITION obanalytics.level3_bitstamp_btcusd_b_pair_id_side_microtimestamp_order__key;


--
-- Name: level3_bitstamp_btcusd_pair_id_side_microtimestamp_order_id_key; Type: INDEX ATTACH; Schema: obanalytics; Owner: 
--

ALTER INDEX obanalytics.level3_bitstamp_pair_id_side_microtimestamp_order_id_event__key ATTACH PARTITION obanalytics.level3_bitstamp_btcusd_pair_id_side_microtimestamp_order_id_key;


--
-- Name: level3_bitstamp_btcusd_s_pair_id_side_microtimestamp_order__key; Type: INDEX ATTACH; Schema: obanalytics; Owner: 
--

ALTER INDEX obanalytics.level3_bitstamp_btcusd_pair_id_side_microtimestamp_order_id_key ATTACH PARTITION obanalytics.level3_bitstamp_btcusd_s_pair_id_side_microtimestamp_order__key;


--
-- Name: level3_bitstamp_ethusd_b_pair_id_side_microtimestamp_order__key; Type: INDEX ATTACH; Schema: obanalytics; Owner: 
--

ALTER INDEX obanalytics.level3_bitstamp_ethusd_pair_id_side_microtimestamp_order_id_key ATTACH PARTITION obanalytics.level3_bitstamp_ethusd_b_pair_id_side_microtimestamp_order__key;


--
-- Name: level3_bitstamp_ethusd_pair_id_side_microtimestamp_order_id_key; Type: INDEX ATTACH; Schema: obanalytics; Owner: 
--

ALTER INDEX obanalytics.level3_bitstamp_pair_id_side_microtimestamp_order_id_event__key ATTACH PARTITION obanalytics.level3_bitstamp_ethusd_pair_id_side_microtimestamp_order_id_key;


--
-- Name: level3_bitstamp_ethusd_s_pair_id_side_microtimestamp_order__key; Type: INDEX ATTACH; Schema: obanalytics; Owner: 
--

ALTER INDEX obanalytics.level3_bitstamp_ethusd_pair_id_side_microtimestamp_order_id_key ATTACH PARTITION obanalytics.level3_bitstamp_ethusd_s_pair_id_side_microtimestamp_order__key;


--
-- Name: level3_bitstamp_ltcusd_b_pair_id_side_microtimestamp_order__key; Type: INDEX ATTACH; Schema: obanalytics; Owner: 
--

ALTER INDEX obanalytics.level3_bitstamp_ltcusd_pair_id_side_microtimestamp_order_id_key ATTACH PARTITION obanalytics.level3_bitstamp_ltcusd_b_pair_id_side_microtimestamp_order__key;


--
-- Name: level3_bitstamp_ltcusd_pair_id_side_microtimestamp_order_id_key; Type: INDEX ATTACH; Schema: obanalytics; Owner: 
--

ALTER INDEX obanalytics.level3_bitstamp_pair_id_side_microtimestamp_order_id_event__key ATTACH PARTITION obanalytics.level3_bitstamp_ltcusd_pair_id_side_microtimestamp_order_id_key;


--
-- Name: level3_bitstamp_ltcusd_s_pair_id_side_microtimestamp_order__key; Type: INDEX ATTACH; Schema: obanalytics; Owner: 
--

ALTER INDEX obanalytics.level3_bitstamp_ltcusd_pair_id_side_microtimestamp_order_id_key ATTACH PARTITION obanalytics.level3_bitstamp_ltcusd_s_pair_id_side_microtimestamp_order__key;


--
-- Name: level3_bitstamp_xrpusd_b_pair_id_side_microtimestamp_order__key; Type: INDEX ATTACH; Schema: obanalytics; Owner: 
--

ALTER INDEX obanalytics.level3_bitstamp_xrpusd_pair_id_side_microtimestamp_order_id_key ATTACH PARTITION obanalytics.level3_bitstamp_xrpusd_b_pair_id_side_microtimestamp_order__key;


--
-- Name: level3_bitstamp_xrpusd_pair_id_side_microtimestamp_order_id_key; Type: INDEX ATTACH; Schema: obanalytics; Owner: 
--

ALTER INDEX obanalytics.level3_bitstamp_pair_id_side_microtimestamp_order_id_event__key ATTACH PARTITION obanalytics.level3_bitstamp_xrpusd_pair_id_side_microtimestamp_order_id_key;


--
-- Name: level3_bitstamp_xrpusd_s_pair_id_side_microtimestamp_order__key; Type: INDEX ATTACH; Schema: obanalytics; Owner: 
--

ALTER INDEX obanalytics.level3_bitstamp_xrpusd_pair_id_side_microtimestamp_order_id_key ATTACH PARTITION obanalytics.level3_bitstamp_xrpusd_s_pair_id_side_microtimestamp_order__key;


--
-- Name: level3_bitstamp check_after_insert; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER check_after_insert AFTER INSERT ON obanalytics.level3_bitstamp FOR EACH ROW EXECUTE PROCEDURE obanalytics.level3_bitstamp_check_after_insert();


--
-- Name: level3 check_microtimestamp_change; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE CONSTRAINT TRIGGER check_microtimestamp_change AFTER UPDATE OF microtimestamp ON obanalytics.level3 DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE PROCEDURE obanalytics.check_microtimestamp_change();


--
-- Name: level3_eras delete_level3_matches; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER delete_level3_matches AFTER DELETE ON obanalytics.level3_eras FOR EACH ROW EXECUTE PROCEDURE obanalytics.level3_eras_delete();


--
-- Name: level3 propagate_microtimestamp_change; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER propagate_microtimestamp_change AFTER UPDATE OF microtimestamp ON obanalytics.level3 FOR EACH ROW WHEN ((old.exchange_id = 2)) EXECUTE PROCEDURE obanalytics.propagate_microtimestamp_change();


--
-- Name: level3 update_chain_after_delete; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER update_chain_after_delete AFTER DELETE ON obanalytics.level3 FOR EACH ROW EXECUTE PROCEDURE obanalytics.level3_update_chain_after_delete();


--
-- Name: level3 update_level3_eras; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER update_level3_eras AFTER INSERT ON obanalytics.level3 REFERENCING NEW TABLE AS inserted FOR EACH STATEMENT EXECUTE PROCEDURE obanalytics.level3_update_level3_eras();


--
-- Name: level3_bitstamp update_level3_eras; Type: TRIGGER; Schema: obanalytics; Owner: ob-analytics
--

CREATE TRIGGER update_level3_eras AFTER INSERT ON obanalytics.level3_bitstamp REFERENCING NEW TABLE AS inserted FOR EACH STATEMENT EXECUTE PROCEDURE obanalytics.level3_update_level3_eras();


--
-- Name: level3 level3_fkey_exchange_id; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE obanalytics.level3
    ADD CONSTRAINT level3_fkey_exchange_id FOREIGN KEY (exchange_id) REFERENCES obanalytics.exchanges(exchange_id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: level3 level3_fkey_pair_id; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE obanalytics.level3
    ADD CONSTRAINT level3_fkey_pair_id FOREIGN KEY (pair_id) REFERENCES obanalytics.pairs(pair_id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: matches live_trades_fkey_exchange_id; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE obanalytics.matches
    ADD CONSTRAINT live_trades_fkey_exchange_id FOREIGN KEY (exchange_id) REFERENCES obanalytics.exchanges(exchange_id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: matches live_trades_fkey_pair_id; Type: FK CONSTRAINT; Schema: obanalytics; Owner: ob-analytics
--

ALTER TABLE obanalytics.matches
    ADD CONSTRAINT live_trades_fkey_pair_id FOREIGN KEY (pair_id) REFERENCES obanalytics.pairs(pair_id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: SCHEMA obanalytics; Type: ACL; Schema: -; Owner: ob-analytics
--

GRANT USAGE ON SCHEMA obanalytics TO obauser;


--
-- Name: TABLE exchanges; Type: ACL; Schema: obanalytics; Owner: ob-analytics
--

GRANT SELECT ON TABLE obanalytics.exchanges TO obauser;


--
-- Name: TABLE pairs; Type: ACL; Schema: obanalytics; Owner: ob-analytics
--

GRANT SELECT ON TABLE obanalytics.pairs TO obauser;


--
-- PostgreSQL database dump complete
--

