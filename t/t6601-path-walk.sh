#!/bin/sh

TEST_PASSES_SANITIZE_LEAK=true

test_description='direct path-walk API tests'

. ./test-lib.sh

test_expect_success 'setup test repository' '
	git checkout -b base &&

	# Make some objects that will only be reachable
	# via non-commit tags.
	mkdir child &&
	echo file >child/file &&
	git add child &&
	git commit -m "will abandon" &&
	git tag -a -m "tree" tree-tag HEAD^{tree} &&
	echo file2 >file2 &&
	git add file2 &&
	git commit --amend -m "will abandon" &&
	git tag tree-tag2 HEAD^{tree} &&

	echo blob >file &&
	blob_oid=$(git hash-object -t blob -w --stdin <file) &&
	git tag -a -m "blob" blob-tag "$blob_oid" &&
	echo blob2 >file2 &&
	blob2_oid=$(git hash-object -t blob -w --stdin <file2) &&
	git tag blob-tag2 "$blob2_oid" &&

	rm -fr child file file2 &&

	mkdir left &&
	mkdir right &&
	echo a >a &&
	echo b >left/b &&
	echo c >right/c &&
	git add . &&
	git commit --amend -m "first" &&
	git tag -m "first" first HEAD &&

	echo d >right/d &&
	git add right &&
	git commit -m "second" &&
	git tag -a -m "second (under)" second.1 HEAD &&
	git tag -a -m "second (top)" second.2 second.1 &&

	# Set up file/dir collision in history.
	rm a &&
	mkdir a &&
	echo a >a/a &&
	echo bb >left/b &&
	git add a left &&
	git commit -m "third" &&
	git tag -a -m "third" third &&

	git checkout -b topic HEAD~1 &&
	echo cc >right/c &&
	git commit -a -m "topic" &&
	git tag -a -m "fourth" fourth
'

test_expect_success 'all' '
	test-tool path-walk -- --all >out &&

	cat >expect <<-EOF &&
	0:COMMIT::$(git rev-parse topic)
	0:COMMIT::$(git rev-parse base)
	0:COMMIT::$(git rev-parse base~1)
	0:COMMIT::$(git rev-parse base~2)
	1:TAG:/tags:$(git rev-parse refs/tags/first)
	1:TAG:/tags:$(git rev-parse refs/tags/second.1)
	1:TAG:/tags:$(git rev-parse refs/tags/second.2)
	1:TAG:/tags:$(git rev-parse refs/tags/third)
	1:TAG:/tags:$(git rev-parse refs/tags/fourth)
	1:TAG:/tags:$(git rev-parse refs/tags/tree-tag)
	1:TAG:/tags:$(git rev-parse refs/tags/blob-tag)
	2:BLOB:/tagged-blobs:$(git rev-parse refs/tags/blob-tag^{})
	2:BLOB:/tagged-blobs:$(git rev-parse refs/tags/blob-tag2^{})
	3:TREE::$(git rev-parse topic^{tree})
	3:TREE::$(git rev-parse base^{tree})
	3:TREE::$(git rev-parse base~1^{tree})
	3:TREE::$(git rev-parse base~2^{tree})
	3:TREE::$(git rev-parse refs/tags/tree-tag^{})
	3:TREE::$(git rev-parse refs/tags/tree-tag2^{})
	4:BLOB:a:$(git rev-parse base~2:a)
	5:TREE:right/:$(git rev-parse topic:right)
	5:TREE:right/:$(git rev-parse base~1:right)
	5:TREE:right/:$(git rev-parse base~2:right)
	6:BLOB:right/d:$(git rev-parse base~1:right/d)
	7:BLOB:right/c:$(git rev-parse base~2:right/c)
	7:BLOB:right/c:$(git rev-parse topic:right/c)
	8:TREE:left/:$(git rev-parse base:left)
	8:TREE:left/:$(git rev-parse base~2:left)
	9:BLOB:left/b:$(git rev-parse base~2:left/b)
	9:BLOB:left/b:$(git rev-parse base:left/b)
	10:TREE:a/:$(git rev-parse base:a)
	11:BLOB:file2:$(git rev-parse refs/tags/tree-tag2^{}:file2)
	12:TREE:child/:$(git rev-parse refs/tags/tree-tag:child)
	13:BLOB:child/file:$(git rev-parse refs/tags/tree-tag:child/file)
	blobs:10
	commits:4
	tags:7
	trees:13
	EOF

	test_cmp_sorted expect out
'

test_expect_success 'indexed objects' '
	test_when_finished git reset --hard &&

	# stage change into index, adding a blob but
	# also invalidating the cache-tree for the root
	# and the "left" directory.
	echo bogus >left/c &&
	git add left &&

	test-tool path-walk -- --indexed-objects >out &&

	cat >expect <<-EOF &&
	0:BLOB:a:$(git rev-parse HEAD:a)
	1:BLOB:left/b:$(git rev-parse HEAD:left/b)
	2:BLOB:left/c:$(git rev-parse :left/c)
	3:BLOB:right/c:$(git rev-parse HEAD:right/c)
	4:BLOB:right/d:$(git rev-parse HEAD:right/d)
	5:TREE:right/:$(git rev-parse topic:right)
	blobs:5
	commits:0
	tags:0
	trees:1
	EOF

	test_cmp_sorted expect out
'

test_expect_success 'branches and indexed objects mix well' '
	test_when_finished git reset --hard &&

	# stage change into index, adding a blob but
	# also invalidating the cache-tree for the root
	# and the "right" directory.
	echo fake >right/d &&
	git add right &&

	test-tool path-walk -- --indexed-objects --branches >out &&

	cat >expect <<-EOF &&
	0:COMMIT::$(git rev-parse topic)
	0:COMMIT::$(git rev-parse base)
	0:COMMIT::$(git rev-parse base~1)
	0:COMMIT::$(git rev-parse base~2)
	1:TREE::$(git rev-parse topic^{tree})
	1:TREE::$(git rev-parse base^{tree})
	1:TREE::$(git rev-parse base~1^{tree})
	1:TREE::$(git rev-parse base~2^{tree})
	2:BLOB:a:$(git rev-parse base~2:a)
	3:TREE:right/:$(git rev-parse topic:right)
	3:TREE:right/:$(git rev-parse base~1:right)
	3:TREE:right/:$(git rev-parse base~2:right)
	4:BLOB:right/d:$(git rev-parse base~1:right/d)
	4:BLOB:right/d:$(git rev-parse :right/d)
	5:BLOB:right/c:$(git rev-parse base~2:right/c)
	5:BLOB:right/c:$(git rev-parse topic:right/c)
	6:TREE:left/:$(git rev-parse base:left)
	6:TREE:left/:$(git rev-parse base~2:left)
	7:BLOB:left/b:$(git rev-parse base:left/b)
	7:BLOB:left/b:$(git rev-parse base~2:left/b)
	8:TREE:a/:$(git rev-parse refs/tags/third:a)
	blobs:7
	commits:4
	tags:0
	trees:10
	EOF

	test_cmp_sorted expect out
'

test_expect_success 'base & topic, sparse' '
	cat >patterns <<-EOF &&
	/*
	!/*/
	/left/
	EOF

	test-tool path-walk --stdin-pl -- base topic <patterns >out &&

	cat >expect <<-EOF &&
	COMMIT::$(git rev-parse topic)
	COMMIT::$(git rev-parse base)
	COMMIT::$(git rev-parse base~1)
	COMMIT::$(git rev-parse base~2)
	commits:4
	TREE::$(git rev-parse topic^{tree})
	TREE::$(git rev-parse base^{tree})
	TREE::$(git rev-parse base~1^{tree})
	TREE::$(git rev-parse base~2^{tree})
	TREE:left/:$(git rev-parse base:left)
	TREE:left/:$(git rev-parse base~2:left)
	trees:6
	BLOB:a:$(git rev-parse base~2:a)
	BLOB:left/b:$(git rev-parse base~2:left/b)
	BLOB:left/b:$(git rev-parse base:left/b)
	blobs:3
	tags:0
	EOF

	sort expect >expect.sorted &&
	sort out >out.sorted &&

	test_cmp expect.sorted out.sorted
'

test_expect_success 'topic only' '
	test-tool path-walk -- topic >out &&

	cat >expect <<-EOF &&
	0:COMMIT::$(git rev-parse topic)
	0:COMMIT::$(git rev-parse base~1)
	0:COMMIT::$(git rev-parse base~2)
	1:TREE::$(git rev-parse topic^{tree})
	1:TREE::$(git rev-parse base~1^{tree})
	1:TREE::$(git rev-parse base~2^{tree})
	2:TREE:right/:$(git rev-parse topic:right)
	2:TREE:right/:$(git rev-parse base~1:right)
	2:TREE:right/:$(git rev-parse base~2:right)
	3:BLOB:right/d:$(git rev-parse base~1:right/d)
	4:BLOB:right/c:$(git rev-parse base~2:right/c)
	4:BLOB:right/c:$(git rev-parse topic:right/c)
	5:TREE:left/:$(git rev-parse base~2:left)
	6:BLOB:left/b:$(git rev-parse base~2:left/b)
	7:BLOB:a:$(git rev-parse base~2:a)
	blobs:5
	commits:3
	tags:0
	trees:7
	EOF

	test_cmp_sorted expect out
'

test_expect_success 'topic, not base' '
	test-tool path-walk -- topic --not base >out &&

	cat >expect <<-EOF &&
	0:COMMIT::$(git rev-parse topic)
	1:TREE::$(git rev-parse topic^{tree})
	2:TREE:right/:$(git rev-parse topic:right)
	3:BLOB:right/d:$(git rev-parse topic:right/d):UNINTERESTING
	4:BLOB:right/c:$(git rev-parse topic:right/c)
	5:TREE:left/:$(git rev-parse topic:left):UNINTERESTING
	6:BLOB:left/b:$(git rev-parse topic:left/b):UNINTERESTING
	7:BLOB:a:$(git rev-parse topic:a):UNINTERESTING
	blobs:4
	commits:1
	tags:0
	trees:3
	EOF

	test_cmp_sorted expect out
'

test_expect_success 'fourth, blob-tag2, not base' '
	test-tool path-walk -- fourth blob-tag2 --not base >out &&

	cat >expect <<-EOF &&
	0:COMMIT::$(git rev-parse topic)
	1:TAG:/tags:$(git rev-parse fourth)
	2:BLOB:/tagged-blobs:$(git rev-parse refs/tags/blob-tag2^{})
	3:TREE::$(git rev-parse topic^{tree})
	4:TREE:right/:$(git rev-parse topic:right)
	5:BLOB:right/d:$(git rev-parse base~1:right/d):UNINTERESTING
	6:BLOB:right/c:$(git rev-parse topic:right/c)
	7:TREE:left/:$(git rev-parse base~1:left):UNINTERESTING
	8:BLOB:left/b:$(git rev-parse base~1:left/b):UNINTERESTING
	9:BLOB:a:$(git rev-parse base~1:a):UNINTERESTING
	blobs:5
	commits:1
	tags:1
	trees:3
	EOF

	test_cmp_sorted expect out
'

test_expect_success 'topic, not base, only blobs' '
	test-tool path-walk --no-trees --no-commits \
		-- topic --not base >out &&

	cat >expect <<-EOF &&
	0:BLOB:right/d:$(git rev-parse topic:right/d):UNINTERESTING
	1:BLOB:right/c:$(git rev-parse topic:right/c)
	2:BLOB:left/b:$(git rev-parse topic:left/b):UNINTERESTING
	3:BLOB:a:$(git rev-parse topic:a):UNINTERESTING
	blobs:4
	commits:0
	tags:0
	trees:0
	EOF

	test_cmp_sorted expect out
'

# No, this doesn't make a lot of sense for the path-walk API,
# but it is possible to do.
test_expect_success 'topic, not base, only commits' '
	test-tool path-walk --no-blobs --no-trees \
		-- topic --not base >out &&

	cat >expect <<-EOF &&
	0:COMMIT::$(git rev-parse topic)
	commits:1
	blobs:0
	tags:0
	trees:0
	EOF

	test_cmp_sorted expect out
'

test_expect_success 'topic, not base, only trees' '
	test-tool path-walk --no-blobs --no-commits \
		-- topic --not base >out &&

	cat >expect <<-EOF &&
	0:TREE::$(git rev-parse topic^{tree})
	1:TREE:right/:$(git rev-parse topic:right)
	2:TREE:left/:$(git rev-parse topic:left):UNINTERESTING
	commits:0
	blobs:0
	tags:0
	trees:3
	EOF

	test_cmp_sorted expect out
'

test_expect_success 'topic, not base, boundary' '
	test-tool path-walk -- --boundary topic --not base >out &&

	cat >expect <<-EOF &&
	0:COMMIT::$(git rev-parse topic)
	0:COMMIT::$(git rev-parse base~1):UNINTERESTING
	1:TREE::$(git rev-parse topic^{tree})
	1:TREE::$(git rev-parse base~1^{tree}):UNINTERESTING
	2:TREE:right/:$(git rev-parse topic:right)
	2:TREE:right/:$(git rev-parse base~1:right):UNINTERESTING
	3:BLOB:right/d:$(git rev-parse base~1:right/d):UNINTERESTING
	4:BLOB:right/c:$(git rev-parse base~1:right/c):UNINTERESTING
	4:BLOB:right/c:$(git rev-parse topic:right/c)
	5:TREE:left/:$(git rev-parse base~1:left):UNINTERESTING
	6:BLOB:left/b:$(git rev-parse base~1:left/b):UNINTERESTING
	7:BLOB:a:$(git rev-parse base~1:a):UNINTERESTING
	blobs:5
	commits:2
	tags:0
	trees:5
	EOF

	test_cmp_sorted expect out
'

test_expect_success 'topic, not base, boundary with pruning' '
	test-tool path-walk --prune -- --boundary topic --not base >out &&

	cat >expect <<-EOF &&
	0:COMMIT::$(git rev-parse topic)
	0:COMMIT::$(git rev-parse base~1):UNINTERESTING
	1:TREE::$(git rev-parse topic^{tree})
	1:TREE::$(git rev-parse base~1^{tree}):UNINTERESTING
	2:TREE:right/:$(git rev-parse topic:right)
	2:TREE:right/:$(git rev-parse base~1:right):UNINTERESTING
	3:BLOB:right/c:$(git rev-parse base~1:right/c):UNINTERESTING
	3:BLOB:right/c:$(git rev-parse topic:right/c)
	blobs:2
	commits:2
	tags:0
	trees:4
	EOF

	test_cmp_sorted expect out
'

test_expect_success 'trees are reported exactly once' '
	test_when_finished "rm -rf unique-trees" &&
	test_create_repo unique-trees &&
	(
		cd unique-trees &&
		mkdir initial &&
		test_commit initial/file &&
		git switch -c move-to-top &&
		git mv initial/file.t ./ &&
		test_tick &&
		git commit -m moved &&
		git update-ref refs/heads/other HEAD
	) &&
	test-tool -C unique-trees path-walk -- --all >out &&
	tree=$(git -C unique-trees rev-parse HEAD:) &&
	grep "$tree" out >out-filtered &&
	test_line_count = 1 out-filtered
'

test_done