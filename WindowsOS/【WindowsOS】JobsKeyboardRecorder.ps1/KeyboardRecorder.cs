// Jobs Windows 键盘会话：仅当前可见进程存活且用户点击开始期间安装键盘钩子。
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;
using System.Drawing;
using Microsoft.Win32;

namespace Jobs.WindowsTools {
    public sealed class KeyboardRecorder : Form {
        private delegate IntPtr KeyboardProcedure(int code, IntPtr message, IntPtr data);
        [DllImport("user32.dll", SetLastError = true)] private static extern IntPtr SetWindowsHookEx(int type, KeyboardProcedure procedure, IntPtr module, uint thread);
        [DllImport("user32.dll", SetLastError = true)] private static extern bool UnhookWindowsHookEx(IntPtr hook);
        [DllImport("user32.dll")] private static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr message, IntPtr data);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr GetModuleHandle(string module);
        private IntPtr hook = IntPtr.Zero;
        private KeyboardProcedure procedure;
        private readonly List<string> entries = new List<string>();
        private readonly Queue<string> pending = new Queue<string>();
        private readonly Label status = new Label();
        private readonly ListBox events = new ListBox();
        private readonly Button start = new Button();
        private readonly Button stop = new Button();
        private readonly Button save = new Button();
        private readonly Timer timer = new Timer();
        private bool recording;
        private bool closing;
        private bool disposed;

        public KeyboardRecorder() {
            Text = "Jobs 键盘记录会话 — 已停止";
            Width = 820;
            Height = 580;
            MinimumSize = new Size(720, 480);
            TopMost = true;
            MinimizeBox = false;
            ShowInTaskbar = true;
            StartPosition = FormStartPosition.CenterScreen;
            Font = new Font("Microsoft YaHei UI", 10);
            var layout = new TableLayoutPanel();
            layout.Dock = DockStyle.Fill;
            layout.RowCount = 4;
            layout.ColumnCount = 1;
            layout.Padding = new Padding(12);
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 105));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 45));
            layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 48));
            var intro = new Label();
            intro.Text = "仅用于你有权操作的当前登录会话。点击“开始”后监听本机会话键盘，始终显示红色状态。\n只记按键名与时间，不转换输入文字、不读取剪贴板或窗口名；按键序列仍可能涉及私人信息。\n停止 / 关闭窗口 / 关闭启动终端后结束监听；不联网、不开机启动、不启动后台进程。\n记录只在内存中，停止后可手动保存；关闭窗口不自动写文件或重建目录。";
            intro.Dock = DockStyle.Fill;
            intro.AutoSize = false;
            status.Dock = DockStyle.Fill;
            status.TextAlign = ContentAlignment.MiddleCenter;
            status.Text = "■ 已停止，没有监听";
            status.BackColor = Color.DarkGreen;
            status.ForeColor = Color.White;
            events.Dock = DockStyle.Fill;
            events.HorizontalScrollbar = true;
            var controls = new FlowLayoutPanel();
            controls.Dock = DockStyle.Fill;
            start.Text = "开始";
            stop.Text = "停止";
            save.Text = "手动保存";
            var clear = new Button();
            clear.Text = "清空内存";
            foreach (var button in new Button[] { start, stop, save, clear }) { button.AutoSize = true; controls.Controls.Add(button); }
            start.Click += delegate { StartRecording(); };
            stop.Click += delegate { StopRecording(); };
            save.Click += delegate { SaveRecording(); };
            clear.Click += delegate { StopRecording(); entries.Clear(); events.Items.Clear(); status.Text = "■ 已停止，内存记录已清空"; };
            layout.Controls.Add(intro, 0, 0);
            layout.Controls.Add(status, 0, 1);
            layout.Controls.Add(events, 0, 2);
            layout.Controls.Add(controls, 0, 3);
            Controls.Add(layout);
            procedure = HandleKeyboard;
            timer.Interval = 100;
            timer.Tick += delegate { FlushPending(); };
            timer.Start();
            SystemEvents.SessionSwitch += SessionChanged;
            FormClosing += delegate { closing = true; StopRecording(); };
            FormClosed += delegate { timer.Stop(); SystemEvents.SessionSwitch -= SessionChanged; };
            VisibleChanged += delegate { if (!Visible && recording) StopRecording(); };
        }
        private void StartRecording() {
            if (recording || closing) return;
            var answer = MessageBox.Show(this, "开始记录当前登录会话的键盘按键名和时间？\n请停止输入密码或私人内容；任何时候点击停止即可结束。", "明确开始记录", MessageBoxButtons.YesNo, MessageBoxIcon.Warning, MessageBoxDefaultButton.Button2);
            if (answer != DialogResult.Yes) return;
            hook = SetWindowsHookEx(13, procedure, GetModuleHandle(null), 0);
            if (hook == IntPtr.Zero) { MessageBox.Show(this, new Win32Exception(Marshal.GetLastWin32Error()).Message, "无法开始监听"); return; }
            recording = true;
            start.Enabled = false;
            save.Enabled = false;
            status.BackColor = Color.DarkRed;
            status.Text = "● 正在记录按键名 — 点击“停止”结束";
            Text = "Jobs 键盘记录会话 — 正在记录";
        }
        private void StopRecording() {
            recording = false;
            if (hook != IntPtr.Zero) {
                IntPtr previous = hook;
                hook = IntPtr.Zero;
                if (!UnhookWindowsHookEx(previous)) {
                    MessageBox.Show("键盘钩子释放失败，程序立即退出以确保停止监听。", "停止会话");
                    Environment.Exit(1);
                }
            }
            FlushPending();
            start.Enabled = !closing;
            save.Enabled = !closing;
            status.BackColor = Color.DarkGreen;
            status.Text = "■ 已停止，没有监听；内存记录 " + entries.Count.ToString() + " 条";
            Text = "Jobs 键盘记录会话 — 已停止";
        }
        private IntPtr HandleKeyboard(int code, IntPtr message, IntPtr data) {
            if (code >= 0 && recording && (message.ToInt64() == 0x100 || message.ToInt64() == 0x104)) {
                int virtualKey = Marshal.ReadInt32(data);
                string line = DateTimeOffset.Now.ToString("yyyy-MM-dd HH:mm:ss.fff zzz") + "\t" + ((Keys)virtualKey).ToString();
                lock (pending) { if (pending.Count < 5000) pending.Enqueue(line); }
            }
            return CallNextHookEx(hook, code, message, data);
        }
        private void FlushPending() {
            lock (pending) {
                while (pending.Count > 0) {
                    string line = pending.Dequeue();
                    entries.Add(line);
                    events.Items.Add(line);
                    if (events.Items.Count > 1000) events.Items.RemoveAt(0);
                }
            }
            if (events.Items.Count > 0) events.TopIndex = events.Items.Count - 1;
            if (recording && entries.Count >= 100000) StopRecording();
        }
        private void SaveRecording() {
            if (recording) return;
            using (var dialog = new SaveFileDialog()) {
                dialog.Title = "手动保存已停止会话的记录";
                dialog.FileName = "JobsKeyboardRecorder-" + DateTime.Now.ToString("yyyyMMdd-HHmmss") + ".tsv";
                dialog.Filter = "按键会话 (*.tsv)|*.tsv|文本文件 (*.txt)|*.txt";
                dialog.CheckPathExists = true;
                dialog.OverwritePrompt = true;
                if (dialog.ShowDialog(this) != DialogResult.OK) return;
                if (!Directory.Exists(Path.GetDirectoryName(dialog.FileName))) { MessageBox.Show(this, "父目录已不存在，拒绝创建或重建目录。"); return; }
                try { File.WriteAllLines(dialog.FileName, entries.ToArray(), new UTF8Encoding(true)); MessageBox.Show(this, "已手动保存：" + dialog.FileName); }
                catch (Exception error) { MessageBox.Show(this, error.Message, "保存失败"); }
            }
        }
        private void SessionChanged(object sender, SessionSwitchEventArgs args) {
            if (args.Reason == SessionSwitchReason.SessionLock || args.Reason == SessionSwitchReason.SessionLogoff || args.Reason == SessionSwitchReason.RemoteDisconnect) {
                if (IsHandleCreated && !IsDisposed) BeginInvoke(new Action(StopRecording));
            }
        }
        public static void Run() {
            Application.EnableVisualStyles();
            using (var form = new KeyboardRecorder()) { Application.Run(form); }
        }
        protected override void Dispose(bool disposing) {
            if (disposing && !disposed) {
                StopRecording();
                disposed = true;
                timer.Stop();
                timer.Dispose();
                SystemEvents.SessionSwitch -= SessionChanged;
            }
            base.Dispose(disposing);
        }
    }
}
