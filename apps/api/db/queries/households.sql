-- name: GetHousehold :one
select * from households
where id = $1;
