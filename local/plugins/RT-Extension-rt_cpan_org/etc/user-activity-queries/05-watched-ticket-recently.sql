-- Users who have added themselves as a watcher to a ticket recently
-- XXX TODO: Merged users aren't treated as such
SELECT
    u.Name as Username,
    count(distinct t.id) as Tickets_watched_in_last_30_days
    FROM Users u
    JOIN Transactions txn
        ON txn.Creator = u.id
    JOIN Tickets t
        ON t.id = txn.ObjectId
       AND txn.ObjectType = 'RT::Ticket'
    JOIN Principals p
        ON p.id = u.id
    JOIN CachedGroupMembers cgm
        ON cgm.MemberId = p.id
    WHERE
           txn.Type = 'AddWatcher'
       AND txn.NewValue = txn.Creator
       AND t.Status != 'deleted'
       AND t.Type = 'ticket'
       AND t.EffectiveId = t.id
       AND p.Disabled = 0
       AND cgm.GroupId = 4
       AND txn.Created > (NOW() - interval 30 day)
    GROUP BY u.Name
    ORDER BY u.Name;
