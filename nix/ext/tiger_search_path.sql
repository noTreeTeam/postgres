CREATE OR REPLACE FUNCTION tiger.AddToSearchPath(varchar)
RETURNS text
AS $$
DECLARE
    var_result text;
    var_cur_search_path text;
BEGIN
    -- Get current search path
    SELECT current_setting('search_path') INTO var_cur_search_path;

    -- If schema is not in search path, add it
    IF NOT var_cur_search_path LIKE '%' || quote_ident($1) || '%' THEN
        var_cur_search_path := var_cur_search_path || ', ' || quote_ident($1);
        EXECUTE 'SET search_path = ' || quote_literal(var_cur_search_path);
    END IF;

    RETURN $1 || ' added to search_path';
END
$$ LANGUAGE plpgsql VOLATILE STRICT SET search_path = pg_catalog;
