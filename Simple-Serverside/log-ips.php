<?php
error_reporting(E_ALL);

date_default_timezone_set('UTC'); // Potential for mistakes

if(isset($_POST['hostname']) && isset($_POST['intip']) && isset($_POST['extip']) && isset($_POST['mydate']) && isset($_POST['note'])) {
    $stamp = date('YmdHis');
    $data = $stamp . ':' . $_POST['hostname'] . ':' . $_POST['intip'] . ':' . $_POST['extip'] . ':' . $_POST['mydate'] . ':' . $_POST['note'] . "\n";
	$filename = "host-check-in.txt";
    if (!file_exists($filename)) {
        $fh = fopen($filename, 'w') or die("Can't create file");
    }
    $ret = file_put_contents($filename, $data, FILE_APPEND | LOCK_EX);
    if($ret === false) {
        die('There was an error writing this file');
    }
    else {
        echo "$ret bytes written to file";
    }
}
else {
   die('no post data to process');
}
?>