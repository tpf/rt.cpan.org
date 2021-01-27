-- Users who have opened a ticket
-- XXX TODO: Merged users aren't treated as such
SELECT
    u.Name as Username,
    count(t.id) as Tickets_created,
    count(CASE WHEN t.Created > (NOW() - interval 30 day) THEN t.id END) as Tickets_created_in_last_30_days
    FROM Tickets t
    JOIN Principals p
        ON p.id = t.Creator
    JOIN Users u
        ON u.id = p.id
    JOIN CachedGroupMembers cgm
        ON cgm.MemberId = p.id
    WHERE
           t.Status != 'deleted'
       AND t.Type = 'ticket'
       AND p.Disabled = 0
       AND cgm.GroupId = 4
    GROUP BY u.Name
    ORDER BY u.Name;
