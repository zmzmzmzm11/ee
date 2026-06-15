// SPDX-License-Identifier: MIT

import { For } from "solid-js";
import { Button, Modal, Tab, Tabs } from "solid-bootstrap";
import { closeHelp, showHelp } from "./Top";

export function HelpModal() {
  return (
    <Modal show={showHelp()} onHide={closeHelp} size={"lg"}>
      <Modal.Body>
        <Tabs activeKey="keyboard">
          <Tab eventKey="keyboard" title="Keyboard Shortcuts">
            <Keyboard />
          </Tab>
        </Tabs>
      </Modal.Body>
      <Modal.Footer>
        <Button variant="secondary" onClick={closeHelp}>
          Close
        </Button>
      </Modal.Footer>
    </Modal>
  );
}

function Keyboard() {
  let key = (k: string) => {
    return <span class="font-monospace">{k}</span>;
  };

  let then = (a: string, b: string) => {
    return (
      <>
        {key(a)} <span class="fw-lighter">then</span> {key(b)}
      </>
    );
  };

  let plus = (a: string, b: string) => {
    return (
      <>
        {key(a)} <span class="fw-lighter">+</span> {key(b)}
      </>
    );
  };

  const shortcuts = [
    [key("?"), "Show help"],
    [then("g", "i"), "Goto inbox"],
    [then("g", "s"), "Goto escalated"],
    [then("g", "a"), "Goto alerts"],
    [key("e"), "Archive selected events, or event at cursor if none selected"],
    [key("F8"), "Archive event at cursor"],
    [plus("Shift", "s"), "Escalate and archive event at cursor"],
    [key("F9"), "Escalate and archive event at cursor"],
    [key("x"), "Select event at cursor"],
    [key("s"), "Escalate selected events, or event at cursor if none selected"],
    [key("j"), "Move cursor to next event"],
    [key("k"), "Move cursor to previous event"],
    [key("."), "Show action menu for event at cursor"],
    [plus("Control", "\\"), "Clear all filters and search"],
    [plus("Shift", "h"), "Goto first row"],
    [plus("Shift", "g"), "Goto last row"],
    [then("*", "a"), "Select all alerts in view"],
    [then("*", "n"), "Deselect all alerts"],
    [then("*", "1"), "Select all alerts with current SID"],
  ];

  return (
    <>
      <p></p>
      <table class={"table table-bordered table-sm p-5"}>
        <tbody class="p-5">
          <For each={shortcuts}>
            {(e, i) => (
              <>
                <tr>
                  <td style={"white-space: nowrap !important;"}>{e[0]}</td>
                  <td>{e[1]}</td>
                </tr>
              </>
            )}
          </For>
        </tbody>
      </table>
    </>
  );
}
