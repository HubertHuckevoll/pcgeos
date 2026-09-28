#!/usr/bin/env python3
"""Runnable check for inline SVG batch admission and pending ownership."""


class Campaign:
    def __init__(self, items):
        self.items = list(items)
        self.next_item = 0
        self.admitted = 0
        self.completed = 0
        self.outstanding = 0
        self.pending = 1                 # campaign hold
        self.paused = 0
        self.max_outstanding = 0
        self.temp_files = 0
        self.batches = []

    def admit(self):
        while (self.next_item < len(self.items) and self.outstanding < 2 and
               self.admitted < 8):
            item = self.items[self.next_item]
            self.next_item += 1
            self.admitted += 1
            if item is True or item == "failure":
                self.completed += 1
            if item is False:
                self.outstanding += 1
                self.pending += 1
                self.temp_files += 1
                self.max_outstanding = max(self.max_outstanding,
                                           self.outstanding)
        self.finish_batch_if_ready()

    def result(self):
        assert self.outstanding
        self.outstanding -= 1
        self.pending -= 1                 # individual import reference
        self.completed += 1
        self.finish_batch_if_ready()
        if not self.paused:
            self.admit()

    def finish_batch_if_ready(self):
        if self.admitted == 8 and self.completed == 8 and not self.outstanding:
            self.batches.append(8)
            if self.next_item < len(self.items):
                self.paused = 30
            else:
                self.pending -= 1         # campaign hold
        elif (self.next_item == len(self.items) and not self.outstanding and
              self.admitted < 8 and self.completed == self.admitted):
            self.batches.append(self.completed)
            self.pending -= 1

    def tick(self, ticks):
        assert self.paused
        self.paused -= ticks
        if not self.paused:
            self.admitted = self.completed = 0
            self.admit()

    def stop(self):
        self.paused = 0
        self.pending -= 1                 # campaign hold

    def cancel_result(self):
        assert self.outstanding
        self.outstanding -= 1
        self.pending -= 1                 # import callback owns this reference


def main():
    # Cache hits count toward each batch without allocating temp files.
    c = Campaign([True, False, True, False, "failure", True, False, True,
                  False, True, False, True, False, False, True, False, True])
    c.admit()
    assert c.max_outstanding == 2
    while c.outstanding:
        c.result()
    assert c.paused == 30 and c.batches == [8]
    c.tick(29)
    assert c.paused == 1 and c.batches == [8]
    c.tick(1)
    assert c.max_outstanding == 2
    while c.outstanding:
        c.result()
    assert c.paused == 30 and c.batches == [8, 8]
    c.tick(30)
    while c.outstanding:
        c.result()
    assert c.batches == [8, 8, 1]
    assert c.pending == 0 and c.temp_files == 8

    stopped = Campaign([False] * 17)
    stopped.admit()
    stopped.result()
    while stopped.outstanding:
        stopped.result()
    assert stopped.paused == 30 and stopped.pending == 1
    stopped.stop()
    assert stopped.paused == 0 and stopped.pending == 0

    active = Campaign([False] * 3)
    active.admit()
    assert active.outstanding == 2 and active.pending == 3
    active.stop()
    assert active.pending == 2
    active.cancel_result()
    active.cancel_result()
    assert active.pending == 0


if __name__ == "__main__":
    main()
